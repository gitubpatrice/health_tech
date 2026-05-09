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

  /// Permanently erases a client, all their animals, all their sessions and
  /// every related attachment. Used for the GDPR right-to-erasure button.
  Future<void> purgeClient(String clientId) async {
    final clientAnimals = await animals.watchByClient(clientId).first;
    for (final a in clientAnimals) {
      await purgeAnimal(a.id);
    }
    final clientSessions = await sessions.watchByClient(clientId).first;
    for (final s in clientSessions) {
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
