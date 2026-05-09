class AppointmentStatus {
  const AppointmentStatus._();
  static const String planned = 'planned';
  static const String confirmed = 'confirmed';
  static const String done = 'done';
  static const String cancelled = 'cancelled';
  static const String noShow = 'no_show';

  static const List<String> all = [planned, confirmed, done, cancelled, noShow];
}

class Appointment {
  const Appointment({
    required this.id,
    required this.startAt,
    required this.endAt,
    this.clientId,
    this.animalId,
    this.sessionId,
    this.title,
    this.location,
    this.kind,
    this.status = AppointmentStatus.planned,
    this.reminderMinutesBefore,
    this.externalCalendarEventId,
    this.externalCalendarId,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? clientId;
  final String? animalId;
  final String? sessionId;
  final DateTime startAt;
  final DateTime endAt;
  final String? title;
  final String? location;
  final String? kind;
  final String status;
  final int? reminderMinutesBefore;
  final String? externalCalendarEventId;
  final String? externalCalendarId;

  /// Free-form decrypted notes (when caller asked for the full mapping).
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Duration get duration => endAt.difference(startAt);

  Appointment copyWith({
    String? id,
    String? clientId,
    String? animalId,
    String? sessionId,
    DateTime? startAt,
    DateTime? endAt,
    String? title,
    String? location,
    String? kind,
    String? status,
    int? reminderMinutesBefore,
    String? externalCalendarEventId,
    String? externalCalendarId,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Appointment(
    id: id ?? this.id,
    clientId: clientId ?? this.clientId,
    animalId: animalId ?? this.animalId,
    sessionId: sessionId ?? this.sessionId,
    startAt: startAt ?? this.startAt,
    endAt: endAt ?? this.endAt,
    title: title ?? this.title,
    location: location ?? this.location,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    reminderMinutesBefore: reminderMinutesBefore ?? this.reminderMinutesBefore,
    externalCalendarEventId:
        externalCalendarEventId ?? this.externalCalendarEventId,
    externalCalendarId: externalCalendarId ?? this.externalCalendarId,
    notes: notes ?? this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
