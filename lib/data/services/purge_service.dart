import '../../domain/attachment.dart';
import '../repositories/animal_repository.dart';
import '../repositories/appointment_repository.dart';
import '../repositories/attachment_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/session_repository.dart';
import 'notification_service.dart';
import 'system_calendar_bridge.dart';

/// Orchestrates cascading soft- and hard-delete across all entities.
///
/// SQLite foreign keys cover row-level dependencies, but several pieces
/// live OUTSIDE the relational graph and must be cascaded explicitly:
///   - **attachments** — linked via a polymorphic `(owner_type, owner_id)`
///     pair, no FK at the DB level
///   - **appointments** — survive the loss of their parent client/animal
///     (FK is `setNull`), so we must soft-delete or purge them ourselves
///   - **system calendar events** — sit in Google Calendar, oblivious to
///     anything we do in our SQLite, so the bridge has to be told
class PurgeService {
  PurgeService({
    required this.clients,
    required this.animals,
    required this.sessions,
    required this.appointments,
    required this.attachments,
    required this.calendar,
    required this.notifications,
  });

  final ClientRepository clients;
  final AnimalRepository animals;
  final SessionRepository sessions;
  final AppointmentRepository appointments;
  final AttachmentRepository attachments;
  final SystemCalendarBridge calendar;
  final NotificationService notifications;

  /// Soft-deletes a client and cascades to their animals, sessions and
  /// appointments. Attachments stay on disk (soft-delete is reversible —
  /// the user can still permanently erase the client later).
  Future<void> softDeleteClient(String clientId) async {
    final clientAnimals = await animals.watchByClient(clientId).first;
    for (final a in clientAnimals) {
      await softDeleteAnimal(a.id);
    }
    final clientSessions = await sessions.watchByClient(clientId).first;
    for (final s in clientSessions) {
      await sessions.softDelete(s.id);
    }
    final clientAppointments = await appointments.watchByClient(clientId).first;
    for (final apt in clientAppointments) {
      await _softDeleteAppointment(
        apt.id,
        apt.externalCalendarId,
        apt.externalCalendarEventId,
      );
    }
    await clients.softDelete(clientId);
  }

  /// Soft-deletes an animal and cascades to its sessions and appointments.
  /// The parent client is left untouched.
  Future<void> softDeleteAnimal(String animalId) async {
    final animalSessions = await sessions.watchByAnimal(animalId).first;
    for (final s in animalSessions) {
      await sessions.softDelete(s.id);
    }
    // Appointments owned by this animal — fetched via a one-shot range
    // query because AppointmentRepository doesn't expose watchByAnimal yet.
    final all = await appointments
        .watchInRange(DateTime(1970), DateTime(2100))
        .first;
    for (final apt in all.where((a) => a.animalId == animalId)) {
      await _softDeleteAppointment(
        apt.id,
        apt.externalCalendarId,
        apt.externalCalendarEventId,
      );
    }
    await animals.softDelete(animalId);
  }

  /// Permanently erases a client, every animal/session/appointment of theirs
  /// and every related attachment + the calendar events they had pushed.
  /// This is the GDPR right-to-erasure path.
  Future<void> purgeClient(String clientId) async {
    final clientAnimals = await animals.watchByClient(clientId).first;
    for (final a in clientAnimals) {
      await purgeAnimal(a.id);
    }
    // After purging animals, only sessions WITHOUT an animal are left to
    // process — animal-bound ones were already cascaded by purgeAnimal.
    final clientSessions = await sessions.watchByClient(clientId).first;
    for (final s in clientSessions.where((x) => x.animalId == null)) {
      await purgeSession(s.id);
    }
    final clientAppointments = await appointments.watchByClient(clientId).first;
    for (final apt in clientAppointments) {
      await _purgeAppointment(
        apt.id,
        apt.externalCalendarId,
        apt.externalCalendarEventId,
      );
    }
    await attachments.purgeAllForOwner(
      ownerType: AttachmentOwner.client,
      ownerId: clientId,
    );
    await clients.purge(clientId);
  }

  Future<void> purgeAnimal(String animalId) async {
    final animalSessions = await sessions.watchByAnimal(animalId).first;
    for (final s in animalSessions) {
      await purgeSession(s.id);
    }
    final all = await appointments
        .watchInRange(DateTime(1970), DateTime(2100))
        .first;
    for (final apt in all.where((a) => a.animalId == animalId)) {
      await _purgeAppointment(
        apt.id,
        apt.externalCalendarId,
        apt.externalCalendarEventId,
      );
    }
    await attachments.purgeAllForOwner(
      ownerType: AttachmentOwner.animal,
      ownerId: animalId,
    );
    await animals.purge(animalId);
  }

  Future<void> purgeSession(String sessionId) async {
    await attachments.purgeAllForOwner(
      ownerType: AttachmentOwner.session,
      ownerId: sessionId,
    );
    await sessions.purge(sessionId);
  }

  /// Soft-deletes a single appointment and best-effort removes its
  /// counterpart in the system calendar (if it had been pushed there).
  Future<void> softDeleteAppointment(String appointmentId) async {
    final apt = await appointments.getById(appointmentId);
    if (apt == null) return;
    await _softDeleteAppointment(
      apt.id,
      apt.externalCalendarId,
      apt.externalCalendarEventId,
    );
  }

  Future<void> _softDeleteAppointment(
    String id,
    String? calendarId,
    String? eventId,
  ) async {
    await appointments.softDelete(id);
    await _removeCalendarEvent(calendarId, eventId);
    await _cancelLocalReminder(id);
  }

  Future<void> _purgeAppointment(
    String id,
    String? calendarId,
    String? eventId,
  ) async {
    await appointments.purge(id);
    await _removeCalendarEvent(calendarId, eventId);
    await _cancelLocalReminder(id);
  }

  /// Local notification cancel is best-effort: any failure (binding not
  /// initialised, permission revoked) must not block the delete.
  Future<void> _cancelLocalReminder(String appointmentId) async {
    try {
      await notifications.cancelFor(appointmentId);
    } on Object {
      // ignore — alarm will fire harmlessly and the receiver will see no
      // matching appointment in DB.
    }
  }

  /// Calendar removal is best-effort: a revoked permission or a missing
  /// calendar app must not break the local delete.
  Future<void> _removeCalendarEvent(String? calendarId, String? eventId) async {
    if (calendarId == null || eventId == null) return;
    try {
      await calendar.remove(calendarId: calendarId, eventId: eventId);
    } on Object {
      // ignore: caller already committed the local delete
    }
  }
}
