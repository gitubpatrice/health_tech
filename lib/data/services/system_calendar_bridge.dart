import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/appointment.dart';

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
  /// When the appointment already carries `externalCalendarEventId` /
  /// `externalCalendarId`, those values are reused so the existing event
  /// is updated in place (instead of creating a duplicate). When they are
  /// null, a fresh event is created in the first writable calendar.
  Future<({String calendarId, String eventId})?> push(
    Appointment appointment,
  ) async {
    if (!await _ensurePermission()) {
      throw const CalendarPermissionDenied();
    }
    await _ensureTimezones();

    final String calendarId;
    if (appointment.externalCalendarId != null) {
      calendarId = appointment.externalCalendarId!;
    } else {
      final cal = await _firstWritableCalendar();
      if (cal == null || cal.id == null) {
        throw const CalendarUnavailable();
      }
      calendarId = cal.id!;
    }

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
    final res = await _plugin.createOrUpdateEvent(event);
    if (res == null || !res.isSuccess) return null;
    final eventId = res.data;
    if (eventId == null) return null;
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
