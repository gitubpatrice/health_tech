import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/database.dart';
import '../data/repositories/animal_repository.dart';
import '../data/repositories/appointment_repository.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/client_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../data/services/backup_service.dart';
import '../data/services/purge_service.dart';
import '../data/services/rgpd_export_service.dart';
import '../data/services/system_calendar_bridge.dart';
import '../data/vault/health_vault.dart';
import '../domain/tag.dart';

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

/// Composite biometric state: whether the device can do strong biometrics
/// AND whether the user has previously enrolled them with Health Tech.
class BiometricStatus {
  const BiometricStatus({required this.available, required this.enrolled});
  final bool available;
  final bool enrolled;
  bool get readyForUnlock => available && enrolled;
}

final biometricStatusProvider = FutureProvider<BiometricStatus>((ref) async {
  final vault = ref.watch(vaultProvider);
  final available = await vault.biometricAvailable();
  final enrolled = await vault.isBiometricEnrolled();
  return BiometricStatus(available: available, enrolled: enrolled);
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

  /// Unlock via the BiometricPrompt + Keystore-wrapped VEK. Returns true
  /// on success, false if the prompt was cancelled or the wrapped blob
  /// failed authentication.
  Future<bool> unlockWithBiometric({
    required String title,
    required String subtitle,
    required String negativeButton,
  }) async {
    final vault = _ref.read(vaultProvider);
    final ok = await vault.unlockWithBiometric(
      title: title,
      subtitle: subtitle,
      negativeButton: negativeButton,
    );
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
  final keyBytes = vault.sqlCipherKeyBytes();
  try {
    final db = await HealthDb.open(vek: keyBytes);
    ref.onDispose(db.close);
    return db;
  } finally {
    keyBytes.fillRange(0, keyBytes.length, 0);
  }
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

/// Live list of every tag in the catalogue, sorted by label. Shared by
/// `TagEditor` (suggestions during typing) and `TagFilterRow` (chips at
/// the top of clients/animals lists) so a single Drift subscription
/// serves both consumers.
final allTagsProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(tagRepositoryProvider).watchAll();
});

final attachmentRepositoryProvider = Provider<AttachmentRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final crypto = ref.watch(vaultProvider).crypto;
  final repo = AttachmentRepository(db, crypto);
  // Sweep stale `.enc` files left behind by previous crashes / partial
  // imports. Runs once per unlock, after a short delay so we don't race
  // with a user who immediately starts importing files (the sweep would
  // otherwise see a fresh `.enc` written but not yet inserted in the DB
  // and remove it as orphan).
  Future.delayed(const Duration(seconds: 5), repo.purgeOrphans);
  return repo;
});

final purgeServiceProvider = Provider((ref) {
  return PurgeService(
    clients: ref.watch(clientRepositoryProvider),
    animals: ref.watch(animalRepositoryProvider),
    sessions: ref.watch(sessionRepositoryProvider),
    appointments: ref.watch(appointmentRepositoryProvider),
    attachments: ref.watch(attachmentRepositoryProvider),
    calendar: ref.watch(systemCalendarBridgeProvider),
  );
});

/// System calendar bridge — opt-in. The user must tick "Add to system
/// calendar" in the appointment form for [SystemCalendarBridge.push] to
/// actually be invoked.
final systemCalendarBridgeProvider = Provider<SystemCalendarBridge>((ref) {
  return SystemCalendarBridge();
});

/// Encrypted device-wide backup. The service reads the open [HealthDb] when
/// the vault is unlocked (export path) and tolerates a closed DB when
/// applying a restore (the database file is overwritten while no handle is
/// open). It deliberately does not `watch` the database future so a locked
/// vault does not throw on construction.
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(dbReader: () => ref.read(databaseProvider).valueOrNull);
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
const _secureChannel = MethodChannel('com.filestech.health_tech/secure_window');

class SecureWindow {
  const SecureWindow._();
  static Future<void> enable() => _secureChannel.invokeMethod('enable');
}
