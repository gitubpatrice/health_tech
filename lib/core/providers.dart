import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/database.dart';
import '../data/repositories/animal_repository.dart';
import '../data/repositories/appointment_repository.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/client_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../data/services/purge_service.dart';
import '../data/services/rgpd_export_service.dart';
import '../data/services/system_calendar_bridge.dart';
import '../data/vault/health_vault.dart';

/// Single instance of the vault for the app lifetime.
final vaultProvider = Provider<HealthVault>((ref) {
  final v = HealthVault();
  ref.onDispose(v.lock);
  return v;
});

/// True once the user has set up the vault at least once on this device.
final vaultInitialisedProvider = FutureProvider<bool>((ref) async {
  return ref.watch(vaultProvider).isInitialised();
});

/// Auth state. `null` = locked, non-null = unlocked.
class VaultSession {
  const VaultSession({required this.unlockedAt});
  final DateTime unlockedAt;
}

class VaultSessionController extends StateNotifier<VaultSession?> {
  VaultSessionController(this._ref) : super(null);
  final Ref _ref;

  Future<bool> setupAndUnlock(String passphrase) async {
    final vault = _ref.read(vaultProvider);
    await vault.setupWithPassphrase(passphrase);
    state = VaultSession(unlockedAt: DateTime.now());
    return true;
  }

  Future<bool> unlock(String passphrase) async {
    final vault = _ref.read(vaultProvider);
    final ok = await vault.unlockWithPassphrase(passphrase);
    if (ok) {
      state = VaultSession(unlockedAt: DateTime.now());
    }
    return ok;
  }

  void lock() {
    _ref.read(vaultProvider).lock();
    state = null;
  }
}

final vaultSessionProvider =
    StateNotifierProvider<VaultSessionController, VaultSession?>(
  VaultSessionController.new,
);

/// Database is opened lazily after unlock and disposed on lock.
final databaseProvider = FutureProvider<HealthDb>((ref) async {
  final session = ref.watch(vaultSessionProvider);
  if (session == null) {
    throw StateError('Database requested while vault is locked');
  }
  final vault = ref.read(vaultProvider);
  final db = await HealthDb.open(passphrase: vault.sqlCipherPassphrase());
  ref.onDispose(db.close);
  return db;
});

/// Repository providers — depend on the unlocked database AND the vault's
/// FieldCrypto. They throw if accessed while locked.
final clientRepositoryProvider = Provider<ClientRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final crypto = ref.watch(vaultProvider).crypto;
  return ClientRepository(db, crypto);
});

final animalRepositoryProvider = Provider<AnimalRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final crypto = ref.watch(vaultProvider).crypto;
  return AnimalRepository(db, crypto);
});

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final crypto = ref.watch(vaultProvider).crypto;
  return SessionRepository(db, crypto);
});

final appointmentRepositoryProvider = Provider<AppointmentRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final crypto = ref.watch(vaultProvider).crypto;
  return AppointmentRepository(db, crypto);
});

final tagRepositoryProvider = Provider<TagRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return TagRepository(db);
});

final attachmentRepositoryProvider = Provider<AttachmentRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final crypto = ref.watch(vaultProvider).crypto;
  return AttachmentRepository(db, crypto);
});

final purgeServiceProvider = Provider((ref) {
  return PurgeService(
    clients: ref.watch(clientRepositoryProvider),
    animals: ref.watch(animalRepositoryProvider),
    sessions: ref.watch(sessionRepositoryProvider),
    attachments: ref.watch(attachmentRepositoryProvider),
  );
});

final systemCalendarBridgeProvider = Provider<SystemCalendarBridge>((ref) {
  return SystemCalendarBridge();
});

final rgpdExportServiceProvider = Provider((ref) {
  return RgpdExportService(
    clients: ref.watch(clientRepositoryProvider),
    animals: ref.watch(animalRepositoryProvider),
    sessions: ref.watch(sessionRepositoryProvider),
    appointments: ref.watch(appointmentRepositoryProvider),
    attachments: ref.watch(attachmentRepositoryProvider),
  );
});

/// SecureWindow channel — `enable` is idempotent. `disable` is intentionally
/// not exposed: FLAG_SECURE is non-negotiable for medical/wellness data and
/// removing it would let screenshots leak sensitive content into the OS
/// recents carousel and accessibility recorders.
const _secureChannel =
    MethodChannel('com.filestech.health_tech/secure_window');

class SecureWindow {
  const SecureWindow._();
  static Future<void> enable() => _secureChannel.invokeMethod('enable');
}
