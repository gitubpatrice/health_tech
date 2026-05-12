import 'package:device_calendar/device_calendar.dart';
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

/// Pushes [Appointment]s into the user's local Android calendar (default
/// app, typically Google Agenda) on demand.
///
/// Strictly opt-in: callers invoke [push] when the user toggles "Add to
/// system calendar". The bridge never syncs silently.
///
/// Timezone handling: we initialise the IANA database lazily and resolve the
/// device's actual zone via flutter_timezone — this avoids the classic
/// daylight-saving drift you get with naive UTC offsets.
class SystemCalendarBridge {
  SystemCalendarBridge([DeviceCalendarPlugin? plugin])
    : _plugin = plugin ?? DeviceCalendarPlugin();

  final DeviceCalendarPlugin _plugin;
  bool _tzReady = false;

  Future<void> _ensureTimezones() async {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
    _tzReady = true;
  }

  Future<bool> _ensurePermission() async {
    final hasPerm = await _plugin.hasPermissions();
    if (hasPerm.isSuccess && (hasPerm.data ?? false)) return true;
    final req = await _plugin.requestPermissions();
    return req.isSuccess && (req.data ?? false);
  }

  Future<Calendar?> _firstWritableCalendar() async {
    final res = await _plugin.retrieveCalendars();
    if (!res.isSuccess) return null;
    final list = res.data ?? <Calendar>[];
    for (final c in list) {
      if ((c.isReadOnly ?? true) == false) return c;
    }
    return null;
  }

  /// Creates OR updates a calendar event for [appointment] and returns the
  /// `(calendarId, eventId)` pair the caller persists on the row.
  ///
  /// Reuses `externalCalendarId` / `externalCalendarEventId` when present
  /// so the existing event is updated in place rather than duplicated.
  Future<({String calendarId, String eventId})?> push(
    Appointment appointment,
  ) async {
    await _ensurePermission(); // throws CalendarPermissionDenied if denied
    await _ensureTimezones();
    final calendarId = await _resolveCalendarId(appointment.externalCalendarId);
    final event = Event(
      calendarId,
      eventId: appointment.externalCalendarEventId,
      title: appointment.title ?? 'Health Tech',
      description: appointment.notes.isEmpty ? null : appointment.notes,
      start: tz.TZDateTime.from(appointment.startAt, tz.local),
      end: tz.TZDateTime.from(appointment.endAt, tz.local),
      location: appointment.location,
      reminders: switch (appointment.reminderMinutesBefore) {
        null => null,
        final int m => <Reminder>[Reminder(minutes: m)],
      },
    );
    return _createOrUpdate(event);
  }

  /// Creates OR updates a calendar event for [session] and returns the
  /// `(calendarId, eventId)` pair. Called automatically on every session save.
  ///
  /// [calendarTitle] is provided by the caller (l10n-aware) since the bridge
  /// has no access to localisation. Reuses existing IDs on edits.
  Future<({String calendarId, String eventId})?> pushSession(
    Session session, {
    required String calendarTitle,
  }) async {
    await _ensurePermission();
    await _ensureTimezones();
    final calendarId = await _resolveCalendarId(session.externalCalendarId);
    final event = Event(
      calendarId,
      eventId: session.externalCalendarEventId,
      title: calendarTitle,
      start: tz.TZDateTime.from(session.startAt, tz.local),
      end: tz.TZDateTime.from(session.endAt, tz.local),
      location: session.location,
    );
    return _createOrUpdate(event);
  }

  // -- private helpers -------------------------------------------------------

  /// Returns the calendar id to use: the existing one if the entity already
  /// has a linked event, otherwise picks the first writable calendar.
  Future<String> _resolveCalendarId(String? existing) async {
    if (existing != null) return existing;
    final cal = await _firstWritableCalendar();
    if (cal == null || cal.id == null) throw const CalendarUnavailable();
    return cal.id!;
  }

  Future<({String calendarId, String eventId})?> _createOrUpdate(
    Event event,
  ) async {
    final res = await _plugin.createOrUpdateEvent(event);
    if (res == null || !res.isSuccess) return null;
    final eventId = res.data;
    final calendarId = event.calendarId;
    if (eventId == null || calendarId == null) return null;
    return (calendarId: calendarId, eventId: eventId);
  }

  Future<void> remove({
    required String calendarId,
    required String eventId,
  }) async {
    if (!await _ensurePermission()) return;
    await _plugin.deleteEvent(calendarId, eventId);
  }
}
