import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/appointment.dart';

/// Résultat de [NotificationService.scheduleFor] — permet à la UI
/// d'informer l'utilisateur quand un rappel n'a pas pu être planifié
/// (cas le plus visible : `skippedPastDue` quand le délai avant RDV est
/// déjà passé au moment de la sauvegarde).
enum ScheduleOutcome {
  /// Rappel programmé avec succès dans la file AlarmManager.
  scheduled,

  /// L'appointment n'avait pas de `reminderMinutesBefore` (ou 0). Aucune
  /// alarme posée — c'est le cas par défaut, pas une erreur.
  noReminder,

  /// Le statut du RDV (cancelled / done) interdit le scheduling. Une
  /// alarme précédente sur le même id a été cancelée.
  skippedStatus,

  /// Le délai-avant calculé tombe dans le passé : l'utilisateur a créé
  /// un RDV à 14h00 alors qu'il était 13h50 avec rappel "15 min avant".
  /// La UI doit informer l'utilisateur (sinon il pense que la notif
  /// arrivera et ne comprend pas pourquoi rien ne fire).
  skippedPastDue,
}

/// Localised strings injected into [NotificationService] from the UI layer.
/// Keeps the service free of `AppL10n` dependencies (no `BuildContext` in
/// services) while still letting the lockscreen + notification shade pick
/// up the user's chosen locale.
class NotificationStrings {
  const NotificationStrings({
    required this.channelName,
    required this.channelDescription,
    required this.defaultTitle,
    required this.bodyMinutesBefore,
  });

  final String channelName;
  final String channelDescription;

  /// Fallback title when `appointment.title` is null/empty.
  final String defaultTitle;

  /// Format function for the notification body. Receives `(minutes, time,
  /// location?)` and returns the human string. Implemented in the UI layer
  /// so it can use the locale's plural / number formatter.
  final String Function(int minutes, String time, String? location)
  bodyMinutesBefore;

  /// Convenience builder: pulls every label from an `AppL10n` instance.
  /// Defined as a static constructor to keep the service file free of any
  /// `flutter` / `material` import.
  static NotificationStrings fromL10n({
    required String channelName,
    required String channelDescription,
    required String defaultTitle,
    required String Function(int minutes, String time) body,
    required String Function(int minutes, String time, String location)
    bodyWithLocation,
  }) {
    return NotificationStrings(
      channelName: channelName,
      channelDescription: channelDescription,
      defaultTitle: defaultTitle,
      bodyMinutesBefore: (m, t, l) =>
          l == null ? body(m, t) : bodyWithLocation(m, t, l),
    );
  }
}

/// Local appointment reminders (no Firebase / FCM — fully on-device).
///
/// Each appointment optionally carries `reminderMinutesBefore`. When set,
/// we schedule a single notification at `startAt - minutesBefore` using
/// AlarmManager via `flutter_local_notifications`. The notification ID is
/// derived deterministically from the appointment id so re-scheduling on
/// edit / cancelling on delete is idempotent — there's exactly one alarm
/// per appointment at any time.
///
/// Boot persistence: reminders survive device reboot via the
/// ScheduledNotificationBootReceiver declared in AndroidManifest.
///
/// Localisation: strings are passed in via [NotificationStrings] at the
/// `scheduleFor` / `rescheduleAll` call site. The service stays UI-agnostic.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialised = false;
  bool _tzReady = false;

  static const _channelId = 'health_tech_appointments_v1';

  Future<void> _ensureTimezones() async {
    // tzdata.initializeTimeZones est idempotent et coûteux uniquement la
    // première fois. setLocalLocation est en revanche réévalué à chaque
    // appel : si l'utilisateur voyage et change de fuseau pendant que
    // l'app tourne (ou redort en background), on veut que le prochain
    // scheduleFor utilise la TZ courante, sinon les notifs partent à
    // l'heure murale de l'ancien fuseau (bug F7 audit failles).
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
  }

  /// Idempotent — call once at app start. Initialises plugin defaults
  /// AND the IANA timezone database we need to convert appointment
  /// `DateTime` values to `tz.TZDateTime`.
  Future<void> ensureInitialised() async {
    if (_initialised) return;
    await _ensureTimezones();
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(init);
    _initialised = true;
  }

  /// Asks Android for POST_NOTIFICATIONS (only relevant on Android 13+).
  /// Returns the granted state. Best-effort: returns false on older OS,
  /// where the permission is implicit.
  Future<bool> requestPermission() async {
    await ensureInitialised();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return true;
    final granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  /// Schedule (or reschedule) the reminder for [appointment]. Always cancels
  /// the previous alarm first so an edit doesn't leave a stale notification
  /// in the queue.
  ///
  /// Retourne [ScheduleOutcome] pour que la UI puisse informer l'utilisateur
  /// quand un rappel est ignoré (statut cancelled/done, ou délai déjà passé).
  /// Sans cette info, l'utilisateur croyait que son rappel était actif et
  /// se plaignait que "la notif n'arrive jamais".
  Future<ScheduleOutcome> scheduleFor(
    Appointment appointment,
    NotificationStrings strings,
  ) async {
    await ensureInitialised();
    final id = _idFor(appointment.id);
    await _plugin.cancel(id);

    final minutesBefore = appointment.reminderMinutesBefore;
    if (minutesBefore == null || minutesBefore <= 0) {
      return ScheduleOutcome.noReminder;
    }
    if (appointment.status == AppointmentStatus.cancelled ||
        appointment.status == AppointmentStatus.done) {
      return ScheduleOutcome.skippedStatus;
    }
    final fireAt = appointment.startAt.subtract(
      Duration(minutes: minutesBefore),
    );
    if (fireAt.isBefore(DateTime.now())) {
      return ScheduleOutcome.skippedPastDue;
    }
    await requestPermission();
    final tzDate = tz.TZDateTime.from(fireAt, tz.local);

    // visibility = secret: lockscreen shows the channel name only, never the
    // appointment title or location. Practitioner data (client name, place)
    // is sensitive — we treat it as we would health notes. The full body is
    // still displayed inside the unlocked notification shade.
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      strings.channelName,
      channelDescription: strings.channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.secret,
    );

    // **DURCISSEMENT C1 audit v1.3.1** : flutter_local_notifications
    // sérialise titre + body + payload dans `databases/<channel>.db`
    // **non chiffrée** pour rejouer les alarms via BootReceiver. Avant
    // ce fix, le titre du RDV (souvent un nom de client) et la location
    // (souvent une adresse client) étaient persistés en clair sur disque,
    // accessibles via ADB / root sans déverrouiller l'app. Maintenant :
    //   - titre = banal (`strings.defaultTitle` = "Rendez-vous")
    //   - body  = générique avec horaire seulement (jamais le lieu)
    //   - payload = appointment.id (UUID, non sensible)
    // Compromis : la lockscreen (visibility = secret) n'a déjà rien
    // d'identifiable ; ouvert dans le shade, l'utilisateur voit l'horaire
    // et clique pour ouvrir l'app qui montre le détail réel.
    final hh = appointment.startAt.hour.toString().padLeft(2, '0');
    final mm = appointment.startAt.minute.toString().padLeft(2, '0');
    // bodyMinutesBefore reçoit `null` en location → le format sans
    // location est utilisé. Plus aucune donnée client en clair plugin-side.
    final body = strings.bodyMinutesBefore(minutesBefore, '$hh:$mm', null);

    await _plugin.zonedSchedule(
      id,
      strings.defaultTitle,
      body,
      tzDate,
      NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: appointment.id,
    );
    return ScheduleOutcome.scheduled;
  }

  Future<void> cancelFor(String appointmentId) async {
    await ensureInitialised();
    await _plugin.cancel(_idFor(appointmentId));
  }

  /// Cancel everything Health Tech ever scheduled — used when the vault
  /// is destroyed or fully restored, so a backup-restored DB doesn't
  /// fight stale alarms from the previous session.
  Future<void> cancelAll() async {
    await ensureInitialised();
    await _plugin.cancelAll();
  }

  /// Re-schedule every appointment in [upcoming] from scratch. Idempotent
  /// AND total : on commence par cancelAll pour évacuer toute alarm zombie
  /// que le BootReceiver aurait remise en file après reboot, ou que la
  /// précédente DB (avant restore) avait laissée. Sans ce cancelAll en
  /// tête, une alarm avec un appointment.id orphelin pourrait fire et
  /// taper sur du vide en handler.
  Future<void> rescheduleAll(
    Iterable<Appointment> upcoming,
    NotificationStrings strings,
  ) async {
    await ensureInitialised();
    try {
      await _plugin.cancelAll();
    } on Object {
      // best-effort : si le cancel global échoue, scheduleFor ci-dessous
      // fera quand même un cancel-puis-schedule par id pour les rdv
      // qu'on connaît. Les zombies inconnus survivront jusqu'au reboot.
    }
    for (final appt in upcoming) {
      try {
        await scheduleFor(appt, strings);
      } on Object {
        // Skip individual failures — one malformed row should not abort
        // the whole reschedule pass.
      }
    }
  }

  /// flutter_local_notifications stores alarms by 32-bit signed int IDs.
  /// We hash the appointment UUID into that range so the same appointment
  /// always maps to the same alarm slot — required for cancel-before-reschedule
  /// to actually cancel the right thing.
  ///
  /// Exposé `@visibleForTesting` pour qu'on puisse vérifier l'absence de
  /// collision sur 100k UUIDs tirés au hasard (probabilité de naissance
  /// ~1.2e-5 sur 31 bits).
  @visibleForTesting
  static int idForTesting(String appointmentId) => _idFor(appointmentId);

  static int _idFor(String appointmentId) {
    var hash = 0x811C9DC5;
    for (final code in appointmentId.codeUnits) {
      hash = (hash ^ code) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    // Map to a positive 31-bit integer so we never produce a negative ID
    // (which the underlying NotificationManager rejects).
    final id = hash & 0x7FFFFFFF;
    // **Audit M10** : id == 0 est légal pour notify() mais cancel(0)
    // sur certaines OEM AOSP-fork annule TOUS les ids de l'app.
    // Probabilité ≈ 2^-31 sur UUID légitime, mais un .htbk forgé peut
    // déclencher la collision. On dégage 0 vers 1 — pas de collision
    // observée car id=1 n'est jamais produit par FNV-1a non-trivial.
    return id == 0 ? 1 : id;
  }
}
