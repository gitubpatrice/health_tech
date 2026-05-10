import '../repositories/appointment_repository.dart';
import 'notification_service.dart';

/// Source unique de vérité pour la synchronisation entre la DB d'appointments
/// et la file d'alarmes AlarmManager.
///
/// Avant ce service, la "réconciliation" était dispersée :
///   - HomeShell.initState appelait `rescheduleAll` au montage.
///   - BackupService.applyRestore appelait `cancelAll` avant le swap DB.
///   - PurgeService.softDeleteAppointment cancelait par id.
///   - VaultLifecycle.factoryReset (futur) devrait aussi tout nettoyer.
///
/// Trois entry points distincts → trois opportunités d'oubli (audit failles
/// F8/F12/F13). Centraliser ici garantit que tous les chemins partagent la
/// même séquence atomique :
///   1. cancelAll (évacue les zombies du BootReceiver / précédent DB)
///   2. query DB pour les rdv à venir
///   3. scheduleFor chaque rdv valide
///
/// Le caller choisit s'il veut juste flush (`flushAll`) ou flush+repopulate
/// (`reconcile`).
class NotificationReconciler {
  NotificationReconciler({
    required this.notifications,
    required this.appointments,
  });

  final NotificationService notifications;
  final AppointmentRepository appointments;

  /// Cancel toutes les alarmes Health Tech, sans rien re-planifier. Utilisé
  /// avant un wipe DB / restore qui va invalider les ids actuels.
  Future<void> flushAll() async {
    await notifications.cancelAll();
  }

  /// Cancel + repopulate à partir de la DB courante. Idempotent : peut
  /// être appelé à chaque déverrouillage / cold-start / post-restore sans
  /// effet de bord. La cible (jusqu'à [limit]) est volontairement large —
  /// un praticien typique a < 200 rdv futurs.
  Future<void> reconcile({
    required NotificationStrings strings,
    int limit = 200,
  }) async {
    final upcoming = await appointments.watchUpcoming(limit: limit).first;
    await notifications.rescheduleAll(upcoming, strings);
  }
}
