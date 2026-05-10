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
  Future<Uint8List> export({required String backupPassphrase}) async {
    if (backupPassphrase.length < 12) {
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
    }
  }

  Future<Uint8List> _buildInnerArchive() async {
    final archive = Archive();
    final pkg = await _packageInfo();
    final manifest = <String, dynamic>{
      'kind': 'health_tech_full_backup',
      'app_version': '${pkg.version}+${pkg.buildNumber}',
      'schema_version': _bundleSchemaVersion,
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
  Future<BackupPreview> previewRestore({
    required Uint8List bundle,
    required String backupPassphrase,
  }) async {
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
    return BackupPreview._(
      archive: archive,
      manifest: manifest,
      headerCreatedAt: parsed.header['created_at'] as String?,
      headerAppVersion: parsed.header['app_version'] as String?,
    );
  }

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

    Map<String, dynamic>? vaultJson;
    var dbWritten = false;
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
        vaultJson = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      }
    }
    if (!dbWritten || vaultJson == null) {
      await stagingDir.delete(recursive: true);
      throw const ValidationError('backup_incomplete', 'bundle');
    }

    // ------------ Phase B: commit (atomic-ish swap) ---------------------
    // Mark the in-flight restore in SharedPreferences. If the OS kills us
    // anywhere below, the next launch will see the flag and offer recovery
    // rather than silently observe an inconsistent state.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kRestorePendingFlag,
      DateTime.now().millisecondsSinceEpoch,
    );
    try {
      // Delete current DB sidecars (WAL/SHM) so SQLCipher does not try to
      // recover from them against the new main file.
      final dbFile = File(p.join(dbDir.path, 'health.db'));
      final wal = File(p.join(dbDir.path, 'health.db-wal'));
      final shm = File(p.join(dbDir.path, 'health.db-shm'));
      if (wal.existsSync()) await wal.delete();
      if (shm.existsSync()) await shm.delete();
      if (dbFile.existsSync()) await dbFile.delete();

      // Wipe current attachments — we own this directory entirely.
      if (attDir.existsSync()) {
        await for (final entity in attDir.list()) {
          if (entity is File) {
            try {
              await entity.delete();
            } on FileSystemException {
              // best-effort: a leftover doesn't compromise the restore.
            }
          }
        }
      }
      if (!dbDir.existsSync()) await dbDir.create(recursive: true);
      if (!attDir.existsSync()) await attDir.create(recursive: true);

      // Rename staging files into place. Same-volume renames are atomic at
      // the inode level on Android.
      await File(p.join(stagingDb.path, 'health.db')).rename(dbFile.path);
      await for (final entity in stagingAtt.list()) {
        if (entity is File) {
          await entity.rename(p.join(attDir.path, p.basename(entity.path)));
        }
      }

      // Apply vault material LAST so a crash before this point leaves the
      // user with the previous wrapped VEK + a fresh DB they cannot decrypt
      // — fail-closed (they retry restore from the same .htbk).
      for (final k in _vaultKeys) {
        final v = vaultJson[k];
        if (v == null) {
          await _storage.delete(key: k);
        } else if (v is String) {
          await _storage.write(key: k, value: v);
        }
      }
    } finally {
      // Remove the staging dir + sentinel as the LAST step. If we ever
      // throw above, the sentinel remains and recoverPartialRestore can
      // resume on next launch.
      if (stagingDir.existsSync()) {
        await stagingDir.delete(recursive: true);
      }
      await prefs.remove(_kRestorePendingFlag);
    }
  }

  /// Recovery hook for a Phase B crash. The LockScreen calls this once at
  /// app start: if the sentinel from a previous interrupted restore is
  /// present, we know the device is in an indeterminate state — the safest
  /// move is to surface the situation rather than silently move on.
  ///
  /// Returns true when a partial restore was detected (caller decides how
  /// to inform the user — typically a banner inviting them to retry the
  /// restore from their .htbk file). Best-effort cleans up the staging
  /// dir so the next attempt starts fresh.
  Future<bool> recoverPartialRestore() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_kRestorePendingFlag);
    if (timestamp == null) return false;
    try {
      final support = await getApplicationSupportDirectory();
      final stagingDir = Directory(p.join(support.path, 'restore_staging'));
      if (stagingDir.existsSync()) {
        await stagingDir.delete(recursive: true);
      }
    } on Object {
      // best-effort cleanup
    }
    await prefs.remove(_kRestorePendingFlag);
    return true;
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
  static const int _kdfMemoryKbFloor = 32 * 1024;
  static const int _kdfIterationsFloor = 2;

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
  /// `.enc` filename. Defends extraction against zip-slip.
  String _safeName(String raw) {
    final base = raw.split(RegExp(r'[\\/]')).last;
    return base.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
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
