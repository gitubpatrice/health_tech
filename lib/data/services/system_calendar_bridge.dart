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
  bool _tzReady = false;

  // ── Permission ─────────────────────────────────────────────────────────────

  Future<void> _ensurePermission() async {
    final hasPerm = await _plugin.hasPermissions();
    if (hasPerm.isSuccess && (hasPerm.data ?? false)) return;
    final req = await _plugin.requestPermissions();
    if (req.isSuccess && (req.data ?? false)) return;
    throw const CalendarPermissionDenied();
  }

  // ── Timezone ───────────────────────────────────────────────────────────────

  Future<void> _ensureTimezones() async {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
    _tzReady = true;
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
  }) async {
    final newEventId = await _ch.invokeMethod<String>('createOrUpdateEvent', {
      'calendarId': calendarId,
      'eventId': ?eventId,
      'title': title,
      'startMs': startAt.millisecondsSinceEpoch,
      'endMs': endAt.millisecondsSinceEpoch,
      'timeZone': tz.local.name,
    });
    return newEventId == null
        ? null
        : (calendarId: calendarId, eventId: newEventId);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Creates or updates a calendar event for [appointment].
  Future<({String calendarId, String eventId})?> push(
    Appointment appointment,
  ) async {
    await _ensurePermission();
    await _ensureTimezones();
    final calendarId = await _resolveCalendarId(appointment.externalCalendarId);
    return _createOrUpdate(
      calendarId: calendarId,
      eventId: appointment.externalCalendarEventId,
      title: appointment.title ?? 'Health Tech',
      startAt: appointment.startAt,
      endAt: appointment.endAt,
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
    );
  }

  /// Removes a previously created calendar event. Best-effort.
  Future<void> remove({
    required String calendarId,
    required String eventId,
  }) async {
    try {
      await _ensurePermission();
    } on CalendarPermissionDenied {
      return;
    }
    try {
      await _ch.invokeMethod<void>('deleteEvent', {'eventId': eventId});
    } on Object {
      // best-effort
    }
  }
}
