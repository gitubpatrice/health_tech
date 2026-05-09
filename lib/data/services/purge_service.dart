import '../../domain/attachment.dart';
import '../repositories/animal_repository.dart';
import '../repositories/attachment_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/session_repository.dart';

/// Orchestrates cascading hard-delete (RGPD right to erasure).
///
/// SQLite cascades take care of row-level dependencies (e.g. animals when
/// their client is dropped) but attachments are linked through a polymorphic
/// `(owner_type, owner_id)` pair, so they need an explicit pass.
class PurgeService {
  PurgeService({
    required this.clients,
    required this.animals,
    required this.sessions,
    required this.attachments,
  });

  final ClientRepository clients;
  final AnimalRepository animals;
  final SessionRepository sessions;
  final AttachmentRepository attachments;

  /// Soft-deletes a client and cascades to their animals + sessions
  /// (attachments stay, since soft-delete is reversible — they will be wiped
  /// only when the user calls [purgeClient]).
  Future<void> softDeleteClient(String clientId) async {
    final clientAnimals = await animals.watchByClient(clientId).first;
    for (final a in clientAnimals) {
      await softDeleteAnimal(a.id);
    }
    final clientSessions = await sessions.watchByClient(clientId).first;
    for (final s in clientSessions) {
      await sessions.softDelete(s.id);
    }
    await clients.softDelete(clientId);
  }

  /// Soft-deletes an animal and cascades to its sessions only (the parent
  /// client stays untouched).
  Future<void> softDeleteAnimal(String animalId) async {
    final animalSessions = await sessions.watchByAnimal(animalId).first;
    for (final s in animalSessions) {
      await sessions.softDelete(s.id);
    }
    await animals.softDelete(animalId);
  }

  /// Permanently erases a client, all their animals, all their sessions and
  /// every related attachment. Used for the GDPR right-to-erasure button.
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
}
