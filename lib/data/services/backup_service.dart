import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors.dart';
import '../../utils/atomic_write.dart';
import '../db/database.dart';
import 'notification_service.dart';

/// Encrypted device-wide backup of the entire vault.
///
/// Two layers of confidentiality:
///   1. The SQLCipher database file is *already* encrypted under the VEK,
///      and every attachment file is *already* encrypted under FieldCrypto.
///      Whoever extracts the inner ZIP without the vault passphrase sees
///      only ciphertext.
///   2. A user-chosen **backup passphrase** (independent of the vault
///      passphrase) wraps the inner ZIP with AES-GCM keyed by Argon2id.
///      The bundle file leaking does not, on its own, reveal anything.
///
/// To restore on the same device or a fresh one the user needs:
///   - the bundle file,
///   - the backup passphrase (decrypts the outer layer),
///   - the vault passphrase (unlocks the restored DB & attachments).
///
/// On-disk format of an `.htbk` bundle:
///   magic        : `HTBK1\n`         (6 bytes)
///   header_len   : uint16 big-endian (2 bytes)
///   header       : JSON              (header_len bytes)
///   ciphertext   : AES-GCM(inner ZIP)
///   mac          : 16 bytes
///
/// Header JSON shape:
///   { "v":1, "kdf":"argon2id", "salt":b64, "memory_kb":n, "iterations":n,
///     "parallelism":n, "nonce":b64, "schema_version":n,
///     "app_version":"x.y.z+n", "created_at":"ISO-8601-UTC" }
class BackupService {
  BackupService({
    required this.dbReader,
    required this.notifications,
    FlutterSecureStorage? secureStorage,
    Future<PackageInfo> Function()? packageInfo,
  }) : _storage =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(
               encryptedSharedPreferences: true,
               resetOnError: false,
             ),
           ),
       _packageInfo = packageInfo ?? PackageInfo.fromPlatform;

  /// Required so `applyRestore` can flush every pending alarm before we
  /// overwrite the database — alarms scheduled against the previous DB
  /// would otherwise fire with payload pointing at appointments that no
  /// longer exist.
  final NotificationService notifications;

  /// Returns the currently-open [HealthDb] when the vault is unlocked, or
  /// null when locked (the export path requires unlocked, the import path
  /// requires locked).
  final HealthDb? Function() dbReader;

  final FlutterSecureStorage _storage;
  final Future<PackageInfo> Function() _packageInfo;

  static const List<int> _magic = [0x48, 0x54, 0x42, 0x4B, 0x31, 0x0A];
  static const int _headerLenSize = 2;
  static const int _macLen = 16;
  static const int _saltLen = 16;
  static const int _nonceLen = 12;

  // Argon2id cost — same wall-clock target as the vault, but cannot calibrate
  // here (the bundle must be portable across devices), so we pick the sturdy
  // mid-range default and embed the parameters in the header.
  static const int _kdfMemoryKb = 64 * 1024;
  static const int _kdfIterations = 3;
  static const int _kdfParallelism = 1;

  static const int _bundleSchemaVersion = 1;

  /// SharedPreferences key signalling that a restore reached Phase B but
  /// did not complete cleanly. Read once at app start by
  /// [recoverPartialRestore]; cleared by [applyRestore] on the happy path.
  static const String _kRestorePendingFlag =
      'health_tech.restore_pending_at_v1';

  /// Compteur de tentatives de recovery, persistant. Au-delà de
  /// [_kMaxRecoveryRetries], on abandonne pour éviter une boucle infinie
  /// au boot (FS bloqué par AV, race avec scan media, etc.). Audit M12.
  static const String _kRestoreRetryCount =
      'health_tech.restore_retry_count_v1';
  static const int _kMaxRecoveryRetries = 3;

  /// Au-delà de cet âge, un staging laissé sur disque est considéré
  /// orphelin (l'utilisateur a probablement réinstallé / fait factory
  /// reset entre temps) et on le wipe sans tenter `_commitStaging`.
  /// Audit M15.
  static const Duration _kStagingMaxAge = Duration(days: 7);

  // Vault material keys mirrored from [HealthVault]. Centralised here so
  // backup format remains stable even if the vault's storage layout shifts.
  static const _vaultKeys = <String>[
    'health_vault.wrapped_vek_v1',
    'health_vault.kdf_salt_v1',
    'health_vault.kdf_memory_v1',
    'health_vault.kdf_iterations_v1',
    'health_vault.kdf_parallelism_v1',
    'health_vault.kdf_backend_v1',
  ];

  // -- Export ---------------------------------------------------------------

  /// Build an encrypted backup bundle. The vault MUST be unlocked: we need
  /// to checkpoint the WAL to copy the database file in a consistent state.
  /// Longueur minimum imposée à la passphrase de sauvegarde. 14 caractères
  /// est le seuil sous lequel un brute-force GPU sur passphrase humaine
  /// (≈ 2-3 bits d'entropie/char) reste réaliste avec Argon2id 64 MiB / 3
  /// itérations. À 14 chars, même une passphrase faiblement entropique
  /// dépasse les semaines de brute-force sur cluster A100.
  static const int _minBackupPassphraseLength = 14;

  Future<Uint8List> export({required String backupPassphrase}) async {
    if (backupPassphrase.length < _minBackupPassphraseLength) {
      throw const ValidationError('backup_passphrase_too_short', 'passphrase');
    }
    final db = dbReader();
    if (db == null) {
      throw const VaultLockedError();
    }
    // Force a full WAL checkpoint so the .db-wal sidecar is folded back into
    // the main file before we read it. Without this, restoring the .db alone
    // on another device would silently lose the most-recent writes.
    await db.customSelect('PRAGMA wal_checkpoint(TRUNCATE);').get();

    final inner = await _buildInnerArchive();
    final salt = _randomBytes(_saltLen);
    final key = await _deriveKey(backupPassphrase, salt);
    final aes = AesGcm.with256bits();
    final nonce = aes.newNonce();
    try {
      // Build the header FIRST so we can pass its bytes as AAD: the AES-GCM
      // tag now authenticates BOTH the ciphertext AND the header. Without
      // this, an attacker could rewrite `iterations: 3 → 1` (or `memory_kb`)
      // in the header without invalidating the MAC, weakening the brute-force
      // budget at restore time. With AAD, any header tweak fails decrypt.
      final pkg = await _packageInfo();
      final headerJson = utf8.encode(
        jsonEncode({
          'v': _bundleSchemaVersion,
          'kdf': 'argon2id',
          'salt': base64Encode(salt),
          'memory_kb': _kdfMemoryKb,
          'iterations': _kdfIterations,
          'parallelism': _kdfParallelism,
          'nonce': base64Encode(nonce),
          'schema_version': _bundleSchemaVersion,
          'app_version': '${pkg.version}+${pkg.buildNumber}',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      if (headerJson.length > 0xFFFF) {
        throw StateError('Header too large for uint16 length prefix');
      }
      final box = await aes.encrypt(
        inner,
        secretKey: SecretKey(key),
        nonce: nonce,
        aad: headerJson,
      );
      final out = BytesBuilder(copy: false);
      out.add(_magic);
      out.add([(headerJson.length >> 8) & 0xFF, headerJson.length & 0xFF]);
      out.add(headerJson);
      out.add(box.cipherText);
      out.add(box.mac.bytes);
      return out.toBytes();
    } finally {
      key.fillRange(0, key.length, 0);
      // Le inner ZIP en clair contenait : la DB SQLCipher (déjà chiffrée
      // mais sa structure révèle quelque chose), les .enc (chiffrés), ET
      // le vault.json (wrapped VEK + KDF salt — chiffré sous master key
      // mais sensible). On wipe le buffer pour réduire la fenêtre où il
      // serait dump-able via une fuite RAM root post-export.
      inner.fillRange(0, inner.length, 0);
    }
  }

  Future<Uint8List> _buildInnerArchive() async {
    final archive = Archive();
    final pkg = await _packageInfo();
    // Le `schema_version` du bundle ≠ le `db_user_version` du DB SQLCipher.
    // L'un versionne le format de l'enveloppe .htbk (cassé seulement si on
    // change la structure inner ZIP), l'autre versionne la structure de
    // la base Drift (cassé à chaque migration). On embarque les deux pour
    // que la restauration puisse refuser un backup créé avec un schéma DB
    // plus récent que celui de l'app courante (sinon drift crash au open
    // avec une assertion peu lisible pour l'utilisateur).
    int? dbUserVersion;
    final db = dbReader();
    if (db != null) {
      try {
        final row = await db.customSelect('PRAGMA user_version').getSingle();
        dbUserVersion = row.read<int>('user_version');
      } on Object {
        // best-effort : si on n'y arrive pas, on omet — la restauration
        // tombera juste sur le check de schéma au prochain ouverture.
      }
    }
    final manifest = <String, dynamic>{
      'kind': 'health_tech_full_backup',
      'app_version': '${pkg.version}+${pkg.buildNumber}',
      'schema_version': _bundleSchemaVersion,
      'db_user_version': ?dbUserVersion,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    _addJson(archive, 'manifest.json', manifest);

    // Vault material — wrapped VEK + KDF params. Without the vault
    // passphrase these bytes remain useless.
    final vaultJson = <String, String?>{};
    for (final k in _vaultKeys) {
      vaultJson[k] = await _storage.read(key: k);
    }
    _addJson(archive, 'vault.json', vaultJson);

    // SQLCipher DB file (already encrypted under the VEK).
    final support = await getApplicationSupportDirectory();
    final dbFile = File(p.join(support.path, 'db', 'health.db'));
    if (dbFile.existsSync()) {
      final bytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('db/health.db', bytes.length, bytes));
    }

    // Attachments — already field-encrypted .enc files. Filenames are random
    // UUIDs (no PII), but we pass them through [_safeName] anyway as a
    // belt-and-braces zip-slip defence on the restore side.
    final attDir = Directory(p.join(support.path, 'attachments'));
    if (attDir.existsSync()) {
      await for (final entity in attDir.list()) {
        if (entity is! File) continue;
        final name = _safeName(p.basename(entity.path));
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile('attachments/$name', bytes.length, bytes));
      }
    }

    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  // -- Restore --------------------------------------------------------------

  /// Verify a bundle and decrypt its inner archive without yet touching
  /// device storage. The caller can preview the manifest, ask the user to
  /// confirm, then call [applyRestore].
  /// Plafond dur sur la taille du bundle .htbk à l'import. Évite qu'un
  /// fichier forgé (zip-bomb, archive géante) ne sature la RAM avant
  /// même que l'envelope ne soit parsée (audit sécu M9/B12).
  /// 256 MiB couvre un coffre praticien réaliste (DB + pièces jointes)
  /// avec une large marge.
  static const int _kMaxBundleBytes = 256 * 1024 * 1024;

  /// Plafond cumulé sur la taille des entrées ZIP décompressées. Bloque
  /// les zip-bombs où une envelope chiffrée modeste contient un ZIP
  /// interne qui se déploie en plusieurs GiB.
  static const int _kMaxArchiveBytes = 384 * 1024 * 1024;

  Future<BackupPreview> previewRestore({
    required Uint8List bundle,
    required String backupPassphrase,
  }) async {
    if (bundle.length > _kMaxBundleBytes) {
      throw const ValidationError('backup_too_large', 'bundle');
    }
    final parsed = _parseEnvelope(bundle);
    final key = await _deriveKey(
      backupPassphrase,
      parsed.salt,
      memoryKb: parsed.memoryKb,
      iterations: parsed.iterations,
      parallelism: parsed.parallelism,
    );
    Uint8List clear;
    try {
      final aes = AesGcm.with256bits();
      final box = SecretBox(
        parsed.cipher,
        nonce: parsed.nonce,
        mac: Mac(parsed.mac),
      );
      try {
        // Pass the header bytes as AAD: must match what was used at
        // encrypt-time, otherwise AES-GCM rejects the tag. Catches the
        // attacker-rewrites-KDF-params attack outright.
        final plain = await aes.decrypt(
          box,
          secretKey: SecretKey(key),
          aad: parsed.headerBytes,
        );
        clear = Uint8List.fromList(plain);
      } on SecretBoxAuthenticationError {
        throw const ValidationError('backup_wrong_passphrase', 'passphrase');
      }
    } finally {
      key.fillRange(0, key.length, 0);
    }
    final archive = ZipDecoder().decodeBytes(clear);
    // Plafond cumulé sur la taille décompressée totale du ZIP interne.
    // Sans ce garde, un attaquant pourrait emballer une charge minuscule
    // chiffrée qui se déploie en plusieurs GiB une fois lue depuis
    // `archive.files` (audit sécu M9/B12).
    var cumulativeBytes = 0;
    for (final f in archive.files) {
      cumulativeBytes += f.size;
      if (cumulativeBytes > _kMaxArchiveBytes) {
        throw const ValidationError('backup_too_large', 'archive');
      }
    }
    final manifestEntry = archive.findFile('manifest.json');
    if (manifestEntry == null) {
      throw const ValidationError('backup_manifest_missing', 'bundle');
    }
    final manifest =
        jsonDecode(utf8.decode(manifestEntry.content as List<int>))
            as Map<String, dynamic>;
    final schema = manifest['schema_version'];
    if (schema is! int || schema > _bundleSchemaVersion) {
      throw const ValidationError(
        'backup_schema_unsupported',
        'schema_version',
      );
    }
    // Si le bundle déclare un `db_user_version` plus récent que celui du
    // schéma Drift de l'app courante, drift refusera d'ouvrir le DB
    // restauré (assertion sur `userVersion > schemaVersion`). On rejette
    // tôt avec un message localisable, plutôt que de laisser drift crash.
    final dbUserVersion = manifest['db_user_version'];
    if (dbUserVersion is int && dbUserVersion > _maxSupportedDbUserVersion) {
      throw const ValidationError(
        'backup_db_version_too_new',
        'db_user_version',
      );
    }
    return BackupPreview._(
      archive: archive,
      manifest: manifest,
      headerCreatedAt: parsed.header['created_at'] as String?,
      headerAppVersion: parsed.header['app_version'] as String?,
    );
  }

  /// Doit être maintenu en phase avec `HealthDb.schemaVersion` — c'est la
  /// version max d'une base que cette release de l'app sait ouvrir. Au
  /// prochain bump de `HealthDb.schemaVersion`, mettre à jour ici aussi.
  static const int _maxSupportedDbUserVersion = 4;

  /// Replace the device's current vault state with the contents of a
  /// previously-validated [BackupPreview]. The vault MUST be locked: we are
  /// about to overwrite the DB file and the attachments directory, and any
  /// open SQLCipher handle would corrupt mid-write.
  ///
  /// Two-phase restore:
  ///   - **Phase A (preparation)**: write every restored file into a
  ///     `restore_staging/` directory under appSupport, and parse the vault
  ///     material out of the bundle. Current device data is **untouched**;
  ///     if anything fails here, the user retries with no harm done.
  ///   - **Phase B (commit)**: tight delete-old / rename-staging / write-vault
  ///     loop. A crash inside Phase B can leave the device in a partial
  ///     state — but the SharedPref sentinel `_kRestorePendingFlag` survives
  ///     and is checked by the LockScreen at next launch (see
  ///     [BackupService.recoverPartialRestore]) so the user gets a clear
  ///     "retry restore" path instead of silent data loss.
  Future<void> applyRestore(BackupPreview preview) async {
    if (dbReader() != null) {
      throw StateError('applyRestore requires the vault to be locked first');
    }
    // Sentinel posé AVANT toute mutation (cancelAll notifs ou wipe staging).
    // Si l'OS kill entre cancelAll et set sentinel, la version précédente
    // perdait silencieusement les alarmes sans aucun marqueur de récupération
    // → utilisateur en mode "mes rappels ne marchent plus, pourquoi ?".
    // Avec le sentinel posé en tête, recoverPartialRestore détecte au moins
    // qu'une opération restore a démarré (et le banner s'affiche).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kRestorePendingFlag,
      DateTime.now().millisecondsSinceEpoch,
    );
    // Flush every alarm before swapping the DB. Without this, the previous
    // device's reminders would still fire — pointing at appointments whose
    // ids no longer match anything in the restored DB. Boot-receiver replay
    // would resurrect them after every reboot too.
    try {
      await notifications.cancelAll();
    } on Object {
      // best-effort: do not block restore on a notif plugin glitch.
    }
    final support = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(support.path, 'db'));
    final attDir = Directory(p.join(support.path, 'attachments'));
    final stagingDir = Directory(p.join(support.path, 'restore_staging'));
    final stagingDb = Directory(p.join(stagingDir.path, 'db'));
    final stagingAtt = Directory(p.join(stagingDir.path, 'attachments'));

    // ------------ Phase A: prepare staging directory --------------------
    // If a previous restore left a half-baked staging dir (e.g. the user
    // killed the app mid-Phase A), wipe it clean before starting over.
    if (stagingDir.existsSync()) {
      await stagingDir.delete(recursive: true);
    }
    await stagingDb.create(recursive: true);
    await stagingAtt.create(recursive: true);

    var dbWritten = false;
    var vaultWritten = false;
    for (final f in preview._archive.files) {
      if (!f.isFile) continue;
      final name = f.name;
      final bytes = Uint8List.fromList(f.content as List<int>);
      // Strict allow-list: ANY entry whose name does not match exactly
      // `db/health.db`, `attachments/<safeName>`, or `vault.json` is
      // silently dropped. Defends against zip-slip — a forged bundle
      // that named an entry `db/../../../shared_prefs/com.filestech.evil.xml`
      // would otherwise escape the destination directory.
      if (name == 'db/health.db') {
        await atomicWriteBytes(
          File(p.join(stagingDb.path, 'health.db')),
          bytes,
        );
        dbWritten = true;
      } else if (name.startsWith('attachments/')) {
        final basename = p.basename(name);
        final safe = _safeName(basename);
        if (safe.isEmpty || safe.contains('..') || safe != basename) {
          continue;
        }
        await atomicWriteBytes(File(p.join(stagingAtt.path, safe)), bytes);
      } else if (name == 'vault.json') {
        // Vault material écrit dans le staging (PAS gardé en mémoire) :
        // recoverPartialRestore peut ainsi finir Phase B après crash sans
        // jamais avoir vu le bundle d'origine.
        await atomicWriteBytes(
          File(p.join(stagingDir.path, 'vault.json')),
          bytes,
        );
        vaultWritten = true;
      }
    }
    if (!dbWritten || !vaultWritten) {
      await stagingDir.delete(recursive: true);
      throw const ValidationError('backup_incomplete', 'bundle');
    }

    // ------------ Phase B: commit (atomic-ish swap) ---------------------
    // Le sentinel _kRestorePendingFlag a été posé en tête de applyRestore
    // (avant cancelAll) et reste set pendant Phase B. Si l'OS kill ici,
    // recoverPartialRestore au prochain boot rejouera _commitStaging.
    final dbFile = File(p.join(dbDir.path, 'health.db'));

    // **Pas de finally autour de prefs.remove** : si _commitStaging throw,
    // on veut que le sentinel SURVIVE pour que recoverPartialRestore tente
    // de finir au prochain boot. L'ancienne version avec
    // `finally { prefs.remove }` perdait le sentinel sur erreur
    // intermédiaire (audit M7).
    await _commitStaging(
      stagingDir: stagingDir,
      dbFile: dbFile,
      attDir: attDir,
    );
    // Succès complet -> on peut nettoyer staging + sentinel.
    try {
      if (stagingDir.existsSync()) {
        await stagingDir.delete(recursive: true);
      }
    } on Object {
      // ignore — staging orphelin sera wipe au prochain applyRestore.
    }
    await prefs.remove(_kRestorePendingFlag);
  }

  /// Phase B factorisée : rename staging → final + apply vault keys.
  /// Idempotente tant que le staging contient `db/health.db` + `vault.json` :
  /// si un fichier cible existe déjà (Phase B ré-exécutée), on l'écrase.
  Future<void> _commitStaging({
    required Directory stagingDir,
    required File dbFile,
    required Directory attDir,
  }) async {
    final stagingDb = File(p.join(stagingDir.path, 'db', 'health.db'));
    final stagingAtt = Directory(p.join(stagingDir.path, 'attachments'));
    final stagingVault = File(p.join(stagingDir.path, 'vault.json'));
    // _commitStaging accepte d'être rejouée avec un staging partiellement
    // consommé : tant que vault.json est présent (étape 4 jamais finalisée),
    // on peut compléter Phase B. La DB en staging est optionnelle
    // (peut-être déjà renommée à destination par une exécution précédente).
    if (!stagingVault.existsSync()) {
      throw const ValidationError('backup_staging_incomplete', 'staging');
    }

    // **Ordre crucial pour idempotence + résistance au crash mid-Phase B**
    // (audit F4) :
    //   1. Wipe sidecars WAL/SHM + attachments existants
    //   2. Rename ATTACHMENTS staging → final D'ABORD
    //   3. Rename DB staging → final EN DERNIER (la présence de la DB
    //      en place sert de sentinel "tout est commité")
    //   4. Apply vault material
    //
    // Si l'OS kill entre (2) et (3) : staging contient encore la DB →
    // recoverPartialRestore relance _commitStaging → l'étape (2) écrase
    // les attachments déjà en place sans perte (ils proviennent du même
    // staging) → étape (3) renomme la DB → succès.
    //
    // Si l'OS kill entre (3) et (4) : staging vide (DB déjà renommée),
    // mais le vault material est toujours dans staging/vault.json →
    // au resume, _commitStaging détecte stagingDb absent + stagingVault
    // présent → applique uniquement le vault material → succès.
    final wal = File(p.join(dbFile.parent.path, 'health.db-wal'));
    final shm = File(p.join(dbFile.parent.path, 'health.db-shm'));
    if (wal.existsSync()) await wal.delete();
    if (shm.existsSync()) await shm.delete();

    if (attDir.existsSync()) {
      await for (final entity in attDir.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } on FileSystemException {
            // best-effort
          }
        }
      }
    }
    if (!dbFile.parent.existsSync()) {
      await dbFile.parent.create(recursive: true);
    }
    if (!attDir.existsSync()) await attDir.create(recursive: true);

    // (2) Attachments d'abord — les renames sont idempotents (rename
    // d'un fichier inexistant = no-op si le `existsSync` ne le voit
    // plus, mais Dart File.rename throw FileSystemException → on guard).
    if (stagingAtt.existsSync()) {
      await for (final entity in stagingAtt.list()) {
        if (entity is File) {
          try {
            await entity.rename(p.join(attDir.path, p.basename(entity.path)));
          } on FileSystemException {
            // best-effort : si un attachment est déjà à destination,
            // l'autre n'est pas perdu pour autant.
          }
        }
      }
    }

    // (3) DB en dernier — `dbFile.delete()` puis rename. Si on crash
    // entre delete et rename : recoverPartialRestore voit dbFile absent
    // mais stagingDb présent → relance le rename idempotent.
    if (dbFile.existsSync()) await dbFile.delete();
    if (stagingDb.existsSync()) {
      await stagingDb.rename(dbFile.path);
    }

    // (4) Apply vault material LAST so a crash before this point leaves
    // the user with the previous wrapped VEK + a fresh DB they cannot
    // decrypt — fail-closed (they retry restore from the same .htbk).
    final vaultJson =
        jsonDecode(await stagingVault.readAsString()) as Map<String, dynamic>;
    for (final k in _vaultKeys) {
      final v = vaultJson[k];
      if (v == null) {
        await _storage.delete(key: k);
      } else if (v is String) {
        await _storage.write(key: k, value: v);
      }
    }
  }

  /// Recovery hook au démarrage de l'app. La LockScreen l'appelle une fois
  /// au build : si le sentinel d'une restauration interrompue est présent,
  /// on TENTE de finir Phase B en utilisant le staging encore sur disque.
  ///
  /// Retourne un [PartialRestoreOutcome] :
  ///   - `none` : pas d'interruption à traiter.
  ///   - `resumed` : le staging était complet (db + vault.json), Phase B
  ///     a été rejouée, le coffre est désormais cohérent. Le user déver-
  ///     rouille avec sa passphrase habituelle, ses données restaurées
  ///     sont là.
  ///   - `aborted` : staging incomplet ou rejouable a échoué — staging
  ///     wipé. Le user voit un banner et doit relancer la restauration
  ///     depuis son .htbk.
  Future<PartialRestoreOutcome> recoverPartialRestore() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_kRestorePendingFlag);
    if (timestamp == null) return PartialRestoreOutcome.none;

    final support = await getApplicationSupportDirectory();
    final stagingDir = Directory(p.join(support.path, 'restore_staging'));
    final stagingDb = File(p.join(stagingDir.path, 'db', 'health.db'));
    final stagingVault = File(p.join(stagingDir.path, 'vault.json'));
    final dbFile = File(p.join(support.path, 'db', 'health.db'));
    final attDir = Directory(p.join(support.path, 'attachments'));

    // **Audit M15** : un staging trop ancien est probablement orphelin
    // (l'utilisateur a réinstallé l'app, ou le device a fait un factory
    // reset partiel). On wipe sans tenter `_commitStaging` pour ne pas
    // committer des bytes pré-historiques sur une session récente.
    final age = DateTime.now().millisecondsSinceEpoch - timestamp;
    if (age < 0 || age > _kStagingMaxAge.inMilliseconds) {
      try {
        if (stagingDir.existsSync()) {
          await stagingDir.delete(recursive: true);
        }
      } on Object {
        // best-effort
      }
      await prefs.remove(_kRestorePendingFlag);
      await prefs.remove(_kRestoreRetryCount);
      return PartialRestoreOutcome.aborted;
    }

    // **Audit M12** : si on a déjà tenté N fois de finir cette restoration
    // sans succès, on abandonne définitivement plutôt que de boucler à
    // chaque démarrage. Évite une app coincée au boot par un FS hostile.
    final retries = prefs.getInt(_kRestoreRetryCount) ?? 0;
    if (retries >= _kMaxRecoveryRetries) {
      try {
        if (stagingDir.existsSync()) {
          await stagingDir.delete(recursive: true);
        }
      } on Object {
        // best-effort
      }
      await prefs.remove(_kRestorePendingFlag);
      await prefs.remove(_kRestoreRetryCount);
      return PartialRestoreOutcome.aborted;
    }

    final canResume =
        stagingDir.existsSync() &&
        stagingDb.existsSync() &&
        stagingVault.existsSync();

    if (canResume) {
      // Incrémente AVANT tentative pour éviter qu'un crash mid-tentative
      // ne fasse re-tenter à l'infini. Si le commit réussit, on supprime
      // le compteur juste après.
      await prefs.setInt(_kRestoreRetryCount, retries + 1);
      try {
        await _commitStaging(
          stagingDir: stagingDir,
          dbFile: dbFile,
          attDir: attDir,
        );
        try {
          if (stagingDir.existsSync()) {
            await stagingDir.delete(recursive: true);
          }
        } on Object {
          // best-effort
        }
        await prefs.remove(_kRestorePendingFlag);
        await prefs.remove(_kRestoreRetryCount);
        return PartialRestoreOutcome.resumed;
      } on Object {
        // L'idempotence du commit a échoué (FS dans un état impossible).
        // Le compteur incrémenté permet d'abandonner après N tentatives.
      }
    }

    try {
      if (stagingDir.existsSync()) {
        await stagingDir.delete(recursive: true);
      }
    } on Object {
      // best-effort cleanup
    }
    await prefs.remove(_kRestorePendingFlag);
    await prefs.remove(_kRestoreRetryCount);
    return PartialRestoreOutcome.aborted;
  }

  // -- Helpers --------------------------------------------------------------

  Future<Uint8List> _deriveKey(
    String passphrase,
    Uint8List salt, {
    int memoryKb = _kdfMemoryKb,
    int iterations = _kdfIterations,
    int parallelism = _kdfParallelism,
  }) async {
    final algo = Argon2id(
      memory: memoryKb,
      parallelism: parallelism,
      iterations: iterations,
      hashLength: 32,
    );
    final key = await algo.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final bytes = await key.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// Reject bundles that declare absurdly weak Argon2id params — they could
  /// only get through here by being forged, since [export] always uses the
  /// safe defaults. Without this floor, an attacker who substitutes the
  /// header (and re-MAC's it under their own passphrase) could feed us a
  /// 1-iteration / 1 MiB derivation and brute-force at will.
  ///
  /// Floor aligned with [_kdfMemoryKb] and [_kdfIterations]: any legitimate
  /// .htbk produced by this app uses exactly those values, so rejecting
  /// anything weaker has zero false-positive cost.
  static const int _kdfMemoryKbFloor = 64 * 1024;
  static const int _kdfIterationsFloor = 3;

  _Envelope _parseEnvelope(Uint8List bundle) {
    if (bundle.length < _magic.length + _headerLenSize + _nonceLen + _macLen) {
      throw const ValidationError('backup_truncated', 'bundle');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bundle[i] != _magic[i]) {
        throw const ValidationError('backup_bad_magic', 'bundle');
      }
    }
    final headerLen = (bundle[_magic.length] << 8) | bundle[_magic.length + 1];
    final headerStart = _magic.length + _headerLenSize;
    if (bundle.length < headerStart + headerLen + _macLen) {
      throw const ValidationError('backup_truncated', 'bundle');
    }
    final headerBytes = bundle.sublist(headerStart, headerStart + headerLen);
    final headerJson =
        jsonDecode(utf8.decode(headerBytes)) as Map<String, dynamic>;
    final salt = base64Decode(headerJson['salt'] as String);
    final nonce = base64Decode(headerJson['nonce'] as String);
    final memoryKb = (headerJson['memory_kb'] as num?)?.toInt() ?? _kdfMemoryKb;
    final iterations =
        (headerJson['iterations'] as num?)?.toInt() ?? _kdfIterations;
    final parallelism =
        (headerJson['parallelism'] as num?)?.toInt() ?? _kdfParallelism;
    if (memoryKb < _kdfMemoryKbFloor || iterations < _kdfIterationsFloor) {
      throw const ValidationError('backup_kdf_params_too_weak', 'bundle');
    }
    final cipherStart = headerStart + headerLen;
    final cipher = bundle.sublist(cipherStart, bundle.length - _macLen);
    final mac = bundle.sublist(bundle.length - _macLen);
    return _Envelope(
      header: headerJson,
      headerBytes: headerBytes,
      salt: salt,
      nonce: nonce,
      memoryKb: memoryKb,
      iterations: iterations,
      parallelism: parallelism,
      cipher: cipher,
      mac: mac,
    );
  }

  void _addJson(Archive archive, String path, Object data) {
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = utf8.encode(json);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  /// Strips any path separator and any character that is not a UUID-shaped
  /// `.enc` filename. Defends extraction against zip-slip. Refuse aussi
  /// les noms commençant par `.` (`.htaccess`, `.nomedia`) — ils n'ont
  /// pas leur place dans `attachments/` et pourraient être interprétés
  /// par une future couche d'indexation Android comme un signal métier.
  String _safeName(String raw) {
    final base = raw.split(RegExp(r'[\\/]')).last;
    final sanitized = base.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    if (sanitized.startsWith('.')) return '_${sanitized.substring(1)}';
    return sanitized;
  }

  static final Random _rng = Random.secure();

  Uint8List _randomBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _rng.nextInt(256);
    }
    return out;
  }
}

/// Résultat de [BackupService.recoverPartialRestore]. La LockScreen mappe
/// chaque variante à un comportement UI distinct (snack / banner / silence).
enum PartialRestoreOutcome {
  /// Aucune restauration interrompue : démarrage normal.
  none,

  /// Une restauration interrompue a été détectée ET reprise avec succès :
  /// la base et le vault sont désormais cohérents. On informe l'utilisateur
  /// par un snack discret pour qu'il sache que ses données sont à jour.
  resumed,

  /// Restauration interrompue détectée mais staging incomplet ou rejouable
  /// échoué : le banner invite l'utilisateur à relancer depuis son .htbk.
  aborted,
}

class BackupPreview {
  BackupPreview._({
    required Archive archive,
    required this.manifest,
    required this.headerCreatedAt,
    required this.headerAppVersion,
  }) : _archive = archive;

  final Archive _archive;
  final Map<String, dynamic> manifest;
  final String? headerCreatedAt;
  final String? headerAppVersion;

  int get attachmentCount =>
      _archive.files.where((f) => f.name.startsWith('attachments/')).length;
  bool get hasDatabase => _archive.findFile('db/health.db') != null;

  /// **Audit M13** : après usage (applyRestore réussi ou aborté), écrase
  /// les bytes en clair encore détenus par l'archive en mémoire. La
  /// preview peut vivre plusieurs minutes dans un dialog de confirmation
  /// pendant que l'utilisateur lit ; un dump RAM root pendant cette
  /// fenêtre exposait `vault.json` clair (wrapped VEK + KDF salt) et
  /// les bytes du DB SQLCipher (chiffrés mais entête identifiante).
  void wipe() {
    for (final f in _archive.files) {
      if (!f.isFile) continue;
      final content = f.content as List<int>;
      for (var i = 0; i < content.length; i++) {
        content[i] = 0;
      }
    }
    _archive.clearSync();
  }
}

class _Envelope {
  _Envelope({
    required this.header,
    required this.headerBytes,
    required this.salt,
    required this.nonce,
    required this.memoryKb,
    required this.iterations,
    required this.parallelism,
    required this.cipher,
    required this.mac,
  });
  final Map<String, dynamic> header;

  /// Raw bytes of the JSON header — needed verbatim as AAD for the AES-GCM
  /// decrypt so the tag also covers the KDF parameters.
  final Uint8List headerBytes;
  final Uint8List salt;
  final Uint8List nonce;
  final int memoryKb;
  final int iterations;
  final int parallelism;
  final Uint8List cipher;
  final Uint8List mac;
}
