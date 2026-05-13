import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/appointment.dart';
import '../../domain/session.dart';

class CalendarPermissionDenied implements Exception {
  const CalendarPermissionDenied();
}

class CalendarUnavailable implements Exception {
  const CalendarUnavailable();
}

/// Pushes Appointments and Sessions into the user's system calendar.
///
/// Permission check uses [DeviceCalendarPlugin.hasPermissions] /
/// [DeviceCalendarPlugin.requestPermissions] (still works on all devices).
///
/// Calendar retrieval and event creation/deletion go through a direct
/// `MethodChannel` to Android's ContentResolver.  The `device_calendar` 4.3.3
/// plugin deserialises Calendar objects as all-null on Samsung Android 14
/// (access-level field mapping regression), so we bypass those methods.
class SystemCalendarBridge {
  SystemCalendarBridge([DeviceCalendarPlugin? plugin])
    : _plugin = plugin ?? DeviceCalendarPlugin();

  final DeviceCalendarPlugin _plugin;
  static const _ch = MethodChannel('com.filestech.health_tech/calendar_sync');
  bool _tzDataLoaded = false;

  /// Titre générique poussé dans le Calendar Android quand on ne souhaite
  /// pas exposer le nom du client. Toute app installée avec READ_CALENDAR
  /// pourrait sinon lire un libellé contenant des données personnelles.
  static const String genericAppointmentTitle = 'Rendez-vous – Health Tech';

  // ── Permission ─────────────────────────────────────────────────────────────

  Future<void> _ensurePermission() async {
    final hasPerm = await _plugin.hasPermissions();
    if (hasPerm.isSuccess && (hasPerm.data ?? false)) return;
    final req = await _plugin.requestPermissions();
    if (req.isSuccess && (req.data ?? false)) return;
    throw const CalendarPermissionDenied();
  }

  // ── Timezone ───────────────────────────────────────────────────────────────

  /// Charge la base tzdata une seule fois (lourd), mais réapplique la
  /// timezone système à chaque appel — l'utilisateur peut voyager entre
  /// deux pushs et le bridge doit refléter sa zone courante (audit code B8).
  Future<void> _ensureTimezones() async {
    if (!_tzDataLoaded) {
      tzdata.initializeTimeZones();
      _tzDataLoaded = true;
    }
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
  }

  // ── Calendar ID resolution (via ContentResolver MethodChannel) ─────────────

  Future<String> _resolveCalendarId(String? existing) async {
    if (existing != null) return existing;
    final id = await _ch.invokeMethod<String>('getFirstWritableCalendarId');
    if (id == null) throw const CalendarUnavailable();
    return id;
  }

  // ── Event write/delete (via ContentResolver MethodChannel) ─────────────────

  Future<({String calendarId, String eventId})?> _createOrUpdate({
    required String calendarId,
    String? eventId,
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    required String ownerId,
  }) async {
    final newEventId = await _ch.invokeMethod<String>('createOrUpdateEvent', {
      'calendarId': calendarId,
      'eventId': ?eventId,
      'title': title,
      'startMs': startAt.millisecondsSinceEpoch,
      'endMs': endAt.millisecondsSinceEpoch,
      'timeZone': tz.local.name,
      'ownerId': ownerId,
    });
    return newEventId == null
        ? null
        : (calendarId: calendarId, eventId: newEventId);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Creates or updates a calendar event for [appointment].
  ///
  /// **Anti-fuite latérale (audit sécu H1)** : par défaut, le titre poussé
  /// dans le Calendar Android est générique. Le titre saisi par
  /// l'utilisateur peut contenir le nom du client ; le Calendar Android
  /// est lisible par toute app disposant de READ_CALENDAR (Gmail, Maps,
  /// agrégateurs, malware opportuniste). On rend ce libellé personnel
  /// opt-in via [includeUserTitleInCalendar] (par défaut `false`).
  Future<({String calendarId, String eventId})?> push(
    Appointment appointment, {
    bool includeUserTitleInCalendar = false,
  }) async {
    await _ensurePermission();
    await _ensureTimezones();
    final calendarId = await _resolveCalendarId(appointment.externalCalendarId);
    final userTitle = appointment.title?.trim();
    final title =
        (includeUserTitleInCalendar &&
            userTitle != null &&
            userTitle.isNotEmpty)
        ? userTitle
        : genericAppointmentTitle;
    return _createOrUpdate(
      calendarId: calendarId,
      eventId: appointment.externalCalendarEventId,
      title: title,
      startAt: appointment.startAt,
      endAt: appointment.endAt,
      ownerId: appointment.id,
    );
  }

  /// Creates or updates a calendar event for [session].
  Future<({String calendarId, String eventId})?> pushSession(
    Session session, {
    required String calendarTitle,
  }) async {
    await _ensurePermission();
    await _ensureTimezones();
    final calendarId = await _resolveCalendarId(session.externalCalendarId);
    return _createOrUpdate(
      calendarId: calendarId,
      eventId: session.externalCalendarEventId,
      title: calendarTitle,
      startAt: session.startAt,
      endAt: session.endAt,
      ownerId: session.id,
    );
  }

  /// Removes a previously created calendar event. Best-effort.
  ///
  /// Renvoie `true` si une ligne a été effacée côté Calendar Android,
  /// `false` si l'event était déjà absent (ou si la permission n'est
  /// pas accordée). Permet au caller de différencier un succès d'un
  /// no-op silencieux (audit code M3).
  Future<bool> remove({
    required String calendarId,
    required String eventId,
  }) async {
    try {
      await _ensurePermission();
    } on CalendarPermissionDenied {
      return false;
    }
    try {
      final rowsDeleted = await _ch.invokeMethod<int>('deleteEvent', {
        'eventId': eventId,
      });
      return (rowsDeleted ?? 0) > 0;
    } on Object {
      return false;
    }
  }
}
