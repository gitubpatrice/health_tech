import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/appointment.dart';

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
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialised = false;
  bool _tzReady = false;

  static const _channelId = 'health_tech_appointments_v1';
  static const _channelName = 'Rendez-vous';
  static const _channelDescription =
      'Rappels avant chaque rendez-vous planifié.';

  Future<void> _ensureTimezones() async {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
    _tzReady = true;
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
  Future<void> scheduleFor(Appointment appointment) async {
    await ensureInitialised();
    final id = _idFor(appointment.id);
    await _plugin.cancel(id);

    final minutesBefore = appointment.reminderMinutesBefore;
    if (minutesBefore == null || minutesBefore <= 0) return;
    if (appointment.status == AppointmentStatus.cancelled ||
        appointment.status == AppointmentStatus.done) {
      return;
    }
    final fireAt = appointment.startAt.subtract(
      Duration(minutes: minutesBefore),
    );
    if (fireAt.isBefore(DateTime.now())) {
      // Past reminder — nothing to schedule. The agenda screen will still
      // show the appointment normally.
      return;
    }
    // Lazily ask for POST_NOTIFICATIONS the first time the user actually
    // schedules a reminder. Asking eagerly at boot would feel intrusive
    // (most practitioners may use the calendar without local pushes).
    // If the user denies, the alarm still fires but the notification is
    // suppressed by Android — no error to surface here.
    await requestPermission();
    final tzDate = tz.TZDateTime.from(fireAt, tz.local);

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );

    await _plugin.zonedSchedule(
      id,
      appointment.title?.isNotEmpty == true
          ? appointment.title!
          : 'Rendez-vous',
      _bodyFor(appointment, minutesBefore),
      tzDate,
      const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // iOS-only knob — required by the API even though we ship Android
      // only. Wall-clock interpretation matches `tz.TZDateTime.from(...)`.
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: appointment.id,
    );
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

  /// flutter_local_notifications stores alarms by 32-bit signed int IDs.
  /// We hash the appointment UUID into that range so the same appointment
  /// always maps to the same alarm slot — required for cancel-before-reschedule
  /// to actually cancel the right thing.
  static int _idFor(String appointmentId) {
    var hash = 0x811C9DC5;
    for (final code in appointmentId.codeUnits) {
      hash = (hash ^ code) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    // Map to a positive 31-bit integer so we never produce a negative ID
    // (which the underlying NotificationManager rejects).
    return hash & 0x7FFFFFFF;
  }

  static String _bodyFor(Appointment a, int minutesBefore) {
    final hh = a.startAt.hour.toString().padLeft(2, '0');
    final mm = a.startAt.minute.toString().padLeft(2, '0');
    final base = 'Dans $minutesBefore min · $hh:$mm';
    if (a.location != null && a.location!.isNotEmpty) {
      return '$base · ${a.location}';
    }
    return base;
  }
}
