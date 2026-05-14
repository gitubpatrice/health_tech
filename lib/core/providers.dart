import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db/database.dart';
import '../data/repositories/animal_repository.dart';
import '../data/repositories/appointment_repository.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/client_repository.dart';
import '../data/repositories/report_template_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../data/services/backup_service.dart';
import '../data/services/global_search_service.dart';
import '../data/services/notification_reconciler.dart';
import '../data/services/notification_service.dart';
import '../data/services/purge_service.dart';
import '../data/services/report_template_seed.dart';
import '../data/services/rgpd_export_service.dart';
import '../data/services/system_calendar_bridge.dart';
import '../data/vault/health_vault.dart';
import '../domain/attachment.dart';
import '../domain/report_template.dart';
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
  // Cas "biométrie supprimée côté Android après opt-in dans l'app" :
  // l'app pense être enrolled (le blob IV/CT vit toujours dans
  // FlutterSecureStorage) mais le hardware n'a plus aucune empreinte
  // STRONG enrôlée. La clé Keystore a déjà été invalidée par Android
  // (`setInvalidatedByBiometricEnrollment`), donc le blob est mort.
  // On auto-nettoie pour que le toggle Settings retombe à OFF — sinon
  // il reste ON greyed-out et l'utilisateur ne comprend pas pourquoi
  // la biométrie ne marche plus.
  if (enrolled && !available) {
    await vault.disableBiometric();
    return const BiometricStatus(available: false, enrolled: false);
  }
  return BiometricStatus(available: available, enrolled: enrolled);
});

/// SharedPref booléen : si l'utilisateur active le « mode strict », la
/// biométrie est désactivée comme raccourci. Force toujours la passphrase
/// à chaque déverrouillage. Permet aux pratiques les plus sensibles
/// d'opter pour un facteur fort exclusif.
const String kStrictModePrefKey = 'auto_lock.strict_mode_v1';

/// Décide à chaque mount du Lock screen si la biométrie est autorisée
/// comme raccourci de déverrouillage. Le LockScreen lit ce provider et
/// désactive l'auto-prompt + le bouton biométrie quand `true`.
///
/// **v1.4.2 — UX terrain** : la fenêtre temporelle "biométrie OK seulement
/// pendant 1h" du modèle 1Password mobile a été retirée. Sur le terrain,
/// fermer l'app le soir et rouvrir le matin tombe systématiquement >1h
/// → passphrase forcée → mauvaise UX pour zéro gain réel (la sécurité du
/// blob biométrique repose sur le Keystore Android, pas sur une fenêtre
/// applicative). Bitwarden, Aegis et Proton Pass autorisent la biométrie
/// sans fenêtre une fois activée. On garde le mode strict pour ceux qui
/// veulent passphrase à chaque ouverture, et l'anti-rollback clock-skew.
final requirePassphraseProvider = FutureProvider<bool>((ref) async {
  // 1) Mode strict (toggle Settings) : passphrase TOUJOURS exigée.
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(kStrictModePrefKey) ?? false) return true;
  // 2) Cold-start (jamais verrouillé sur ce device, ou destroy()) ->
  // passphrase. La biométrie ne peut pas être un facteur unique au
  // tout premier déverrouillage : le wrap Keystore n'existe pas encore.
  final lastLocked = await ref.read(vaultProvider).lastLockedAtMs();
  if (lastLocked == null) return true;
  // 3) Anti-rollback : un attaquant root pourrait reculer le clock système
  // pour effacer un éventuel marqueur futur. `elapsed < 0` ⇒ clock reculé
  // ⇒ on force la passphrase par précaution. (Pas de borne haute :
  // la biométrie reste OK quel que soit le délai depuis le dernier lock.)
  final elapsed = DateTime.now().millisecondsSinceEpoch - lastLocked;
  if (elapsed < 0) return true;
  return false;
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

  /// Lock asynchrone : on attend la fermeture effective du handle SQLCipher
  /// AVANT de wiper le VEK. Sinon Drift peut continuer à écrire WAL/SHM
  /// pendant que `vault.lock()` zéroïse la clé en mémoire — n'importe
  /// quelle requête en vol fait alors throw `SecretBoxAuthenticationError`,
  /// et — plus grave — `BackupService.applyRestore` peut se mettre à
  /// supprimer `health.db` alors que SQLCipher tient encore le file
  /// descriptor ouvert (corruption WAL/SHM possible).
  Future<void> lock() async {
    final dbAsync = _ref.read(databaseProvider);
    if (dbAsync.hasValue) {
      try {
        await dbAsync.requireValue.close();
      } on Object {
        // ignore — on continue le lock même si close throw, pour ne pas
        // laisser le vault déverrouillé après une demande utilisateur.
      }
    }
    // **Durcissement audit v1.3.1 H5** : Image.memory() (utilisé dans
    // AttachmentViewer pour les photos santé) garde le bitmap décodé
    // dans PaintingBinding.imageCache (par défaut 100 Mo). Au lock,
    // on wipe le VEK mais cette cache restait chaude → un dump RAM
    // root après lock pouvait encore lire les pixels d'une photo
    // d'examen médical. Maintenant : clear + clearLiveImages.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
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

/// CRUD live des modèles de comptes rendus (DB v6, v1.6.0). Idempotent et
/// stateless — pas de chiffrement champ-à-champ.
final reportTemplateRepositoryProvider = Provider<ReportTemplateRepository>((
  ref,
) {
  final db = ref.watch(databaseProvider).requireValue;
  return ReportTemplateRepository(db);
});

/// Stream live de TOUS les templates (tri système d'abord puis nom).
/// Alimente l'écran Réglages → Modèles de comptes rendus.
///
/// **`autoDispose`** (audit v1.6.0 P3) : l'écran Réglages n'est ouvert
/// que rarement, le stream Drift n'a aucune raison de rester abonné en
/// arrière-plan pendant que l'utilisateur travaille dans Sessions ou
/// Agenda. Riverpod ferme l'abonnement dès que plus aucun widget ne
/// `watch()` ce provider.
final allReportTemplatesProvider =
    StreamProvider.autoDispose<List<ReportTemplate>>((ref) {
      return ref.watch(reportTemplateRepositoryProvider).watchAll();
    });

/// Stream live filtré par `SessionKind` — alimente le `BottomSheet`
/// "Insérer un modèle" du formulaire de séance. Les templates `other`
/// et `distance` sont toujours inclus côté repository.
///
/// **`autoDispose`** (audit v1.6.0 P2) : la BottomSheet du formulaire de
/// séance est éphémère ; sans autoDispose, chaque ouverture (avec un
/// `kind` potentiellement différent) accumulerait une subscription Drift
/// orpheline jusqu'au lock.
final reportTemplatesByKindProvider = StreamProvider.autoDispose
    .family<List<ReportTemplate>, String>(
      (ref, kind) =>
          ref.watch(reportTemplateRepositoryProvider).watchByKind(kind),
    );

/// One-shot seed des canevas par défaut au 1er unlock après upgrade vers
/// v1.6.0. Appelé depuis `HomeShell.initState` (post-frame) ; idempotent :
/// si la table contient déjà ≥ 1 template `is_system = 1`, ne fait rien.
///
/// La `Locale` est lue depuis `PlatformDispatcher.instance.locale` au
/// moment du seed (post-unlock, post-frame) — audit v1.6.0 C8 / G2 :
/// avant, `Locale('fr')` codé en dur ignorait les utilisateur·ices EN.
final reportTemplateSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.watch(reportTemplateRepositoryProvider);
  final seed = ReportTemplateSeed(repo);
  final systemLocale = PlatformDispatcher.instance.locale;
  await seed.seedDefaultsIfEmpty(locale: systemLocale);
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
  // with a user who immediately starts importing files. On lock, le Timer
  // est annulé via ref.onDispose pour qu'un purgeOrphans ne tourne pas
  // sur un repo dont la DB a été fermée entre-temps (race observée dans
  // l'audit P1-7).
  final timer = Timer(const Duration(seconds: 5), () {
    unawaited(repo.purgeOrphans());
  });
  ref.onDispose(timer.cancel);
  return repo;
});

/// Clé d'identification d'un propriétaire d'avatar — alias récord pour ne
/// pas refabriquer un type partout. `(ownerType, ownerId)` est l'identifiant
/// polymorphe utilisé partout dans `AttachmentRepository`.
typedef AvatarOwnerKey = ({String ownerType, String ownerId});

/// Stream live de l'avatar (au plus un par owner). Émet `null` quand aucune
/// photo n'est définie. Riverpod cache la subscription tant qu'au moins un
/// widget la `watch()`. `autoDispose` : la photo n'a aucune raison de
/// rester abonnée en mémoire quand l'écran qui l'affiche se ferme.
final ownerAvatarProvider = StreamProvider.autoDispose
    .family<Attachment?, AvatarOwnerKey>((ref, key) {
      return ref
          .watch(attachmentRepositoryProvider)
          .watchAvatar(ownerType: key.ownerType, ownerId: key.ownerId);
    });

/// Bytes déchiffrés d'un attachment donné (avatar ou autre). Family-keyed
/// par `attachmentId` : si la même photo est rendue dans plusieurs widgets
/// (liste + détail), on ne paie qu'un seul `decryptBytes`. `autoDispose`
/// pour libérer les bytes en RAM quand plus aucun widget ne les utilise —
/// la `PaintingBinding.imageCache` Flutter prend ensuite le relais pour
/// les bitmaps décodés (et est déjà clear au lock dans
/// `VaultSessionController.lock`).
final attachmentBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, attachmentId) {
      return ref
          .watch(attachmentRepositoryProvider)
          .readBytes(attachmentId);
    });

final purgeServiceProvider = Provider((ref) {
  return PurgeService(
    clients: ref.watch(clientRepositoryProvider),
    animals: ref.watch(animalRepositoryProvider),
    sessions: ref.watch(sessionRepositoryProvider),
    appointments: ref.watch(appointmentRepositoryProvider),
    attachments: ref.watch(attachmentRepositoryProvider),
    calendar: ref.watch(systemCalendarBridgeProvider),
    notifications: ref.watch(notificationServiceProvider),
  );
});

/// System calendar bridge — opt-in. The user must tick "Add to system
/// calendar" in the appointment form for [SystemCalendarBridge.push] to
/// actually be invoked.
final systemCalendarBridgeProvider = Provider<SystemCalendarBridge>((ref) {
  return SystemCalendarBridge();
});

/// Cross-entity search across clients/animals/sessions/appointments.
/// Searches plaintext columns only — encrypted notes stay opaque on
/// purpose (they can't appear in any future FTS index either).
final globalSearchServiceProvider = Provider<GlobalSearchService>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return GlobalSearchService(db);
});

/// On-device appointment reminder scheduler. Stateless wrapper around
/// `flutter_local_notifications` — kept as a singleton so the
/// `_initialised` / `_tzReady` caches survive across screens.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

/// Source unique de vérité pour la synchronisation file d'alarmes ↔ DB.
/// Tous les chemins (boot post-unlock, post-restore, post-destroy) doivent
/// passer par ici plutôt que d'appeler directement
/// `notifications.cancelAll` / `rescheduleAll` au risque d'oublier l'un.
final notificationReconcilerProvider = Provider<NotificationReconciler>((ref) {
  return NotificationReconciler(
    notifications: ref.watch(notificationServiceProvider),
    appointments: ref.watch(appointmentRepositoryProvider),
  );
});

/// Encrypted device-wide backup. The service reads the open [HealthDb] when
/// the vault is unlocked (export path) and tolerates a closed DB when
/// applying a restore (the database file is overwritten while no handle is
/// open). It deliberately does not `watch` the database future so a locked
/// vault does not throw on construction.
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    dbReader: () => ref.read(databaseProvider).valueOrNull,
    notifications: ref.read(notificationServiceProvider),
  );
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
