import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/core/errors.dart';
import 'package:health_tech/data/db/database.dart';
import 'package:health_tech/data/services/backup_service.dart';
import 'package:health_tech/data/services/notification_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// In-memory FlutterSecureStorage stand-in — copié de health_vault_test.
/// Évite de monter le canal natif EncryptedSharedPreferences pour les
/// tests pure-Dart de BackupService.
class _MemoryStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Construit un bundle .htbk synthétique pour les tests : nous reproduisons
/// le format à la main pour tester la robustesse de [BackupService.previewRestore]
/// face à des bundles légitimes ET forgés (header modifié, KDF affaibli, etc.).
///
/// Format rappelé :
///   magic "HTBK1\n"     (6 bytes)
///   header_len uint16 BE (2 bytes)
///   header JSON         (header_len bytes)
///   ciphertext          (variable)
///   mac                 (16 bytes)
Future<Uint8List> _forgeBundle({
  required String passphrase,
  required Uint8List innerZip,
  int memoryKb = 64 * 1024,
  int iterations = 3,
  int parallelism = 1,
  int? overrideMemoryKbInHeader,
  int? overrideIterationsInHeader,
}) async {
  // Argon2id derive
  final salt = Uint8List.fromList(List.generate(16, (i) => i + 1));
  final algo = Argon2id(
    memory: memoryKb,
    parallelism: parallelism,
    iterations: iterations,
    hashLength: 32,
  );
  final secretKey = await algo.deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: salt,
  );
  final keyBytes = await secretKey.extractBytes();

  // Header — on permet d'OVERRIDE memory_kb / iterations pour simuler un
  // attaquant qui rewrite le header sans rederiver. AAD couvre le header
  // verbatim, donc l'override doit aussi être pris comme AAD.
  final aes = AesGcm.with256bits();
  final nonce = aes.newNonce();
  final headerJson = utf8.encode(
    jsonEncode({
      'v': 1,
      'kdf': 'argon2id',
      'salt': base64Encode(salt),
      'memory_kb': overrideMemoryKbInHeader ?? memoryKb,
      'iterations': overrideIterationsInHeader ?? iterations,
      'parallelism': parallelism,
      'nonce': base64Encode(nonce),
      'schema_version': 1,
      'app_version': '1.0.0+1',
      'created_at': '2026-05-10T00:00:00.000Z',
    }),
  );

  final box = await aes.encrypt(
    innerZip,
    secretKey: SecretKey(keyBytes),
    nonce: nonce,
    aad: headerJson,
  );

  final out = BytesBuilder(copy: false);
  out.add([0x48, 0x54, 0x42, 0x4B, 0x31, 0x0A]); // HTBK1\n
  out.add([(headerJson.length >> 8) & 0xFF, headerJson.length & 0xFF]);
  out.add(headerJson);
  out.add(box.cipherText);
  out.add(box.mac.bytes);
  return out.toBytes();
}

/// Construit un inner ZIP minimal mais conforme : manifest.json + vault.json
/// + db/health.db (un blob factice — previewRestore ne valide pas le contenu
/// SQLCipher, juste la présence du fichier).
Uint8List _minimalInnerZip() {
  final archive = Archive();
  final manifest = utf8.encode(
    jsonEncode({
      'kind': 'health_tech_full_backup',
      'app_version': '1.0.0+1',
      'schema_version': 1,
      'db_user_version': 3,
      'created_at': '2026-05-10T00:00:00.000Z',
    }),
  );
  archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
  final vault = utf8.encode(jsonEncode(<String, String>{}));
  archive.addFile(ArchiveFile('vault.json', vault.length, vault));
  final dbBytes = Uint8List.fromList(List.filled(64, 0xAB));
  archive.addFile(ArchiveFile('db/health.db', dbBytes.length, dbBytes));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BackupService service;

  setUp(() {
    service = BackupService(
      dbReader: () => null,
      notifications: NotificationService(),
      secureStorage: _MemoryStorage(),
      packageInfo: () async => PackageInfo(
        appName: 'test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
      ),
    );
  });

  group('previewRestore', () {
    test('round-trip d\'un bundle legitime', () async {
      final bundle = await _forgeBundle(
        passphrase: 'correct horse battery stapler',
        innerZip: _minimalInnerZip(),
      );
      final preview = await service.previewRestore(
        bundle: bundle,
        backupPassphrase: 'correct horse battery stapler',
      );
      expect(preview.hasDatabase, isTrue);
      expect(preview.attachmentCount, 0);
    });

    test('rejette une passphrase incorrecte (AES-GCM auth fail)', () async {
      final bundle = await _forgeBundle(
        passphrase: 'correct horse battery stapler',
        innerZip: _minimalInnerZip(),
      );
      expect(
        () => service.previewRestore(
          bundle: bundle,
          backupPassphrase: 'wrong passphrase here',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.code,
            'code',
            'backup_wrong_passphrase',
          ),
        ),
      );
    });

    test('rejette un header AAD trafiqué (memory_kb réécrit)', () async {
      // Bundle légitime avec params forts dans la KDF, mais header
      // déclare params faibles. AAD couvre le header → MAC invalide.
      final bundle = await _forgeBundle(
        passphrase: 'correct horse battery stapler',
        innerZip: _minimalInnerZip(),
        memoryKb: 64 * 1024,
        iterations: 3,
        overrideIterationsInHeader: 1,
        overrideMemoryKbInHeader: 1024,
      );
      // Le header weakening est rejeté AVANT decrypt par le floor check :
      // _kdfMemoryKbFloor = 64 MiB, _kdfIterationsFloor = 3.
      expect(
        () => service.previewRestore(
          bundle: bundle,
          backupPassphrase: 'correct horse battery stapler',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.code,
            'code',
            'backup_kdf_params_too_weak',
          ),
        ),
      );
    });

    test('rejette un magic byte invalide', () async {
      final bundle = await _forgeBundle(
        passphrase: 'correct horse battery stapler',
        innerZip: _minimalInnerZip(),
      );
      bundle[0] = 0x00; // casse le magic
      expect(
        () => service.previewRestore(
          bundle: bundle,
          backupPassphrase: 'correct horse battery stapler',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.code,
            'code',
            'backup_bad_magic',
          ),
        ),
      );
    });

    test('rejette un bundle tronqué', () async {
      final bundle = Uint8List(
        20,
      ); // trop court pour magic+header_len+nonce+mac
      bundle[0] = 0x48;
      bundle[1] = 0x54;
      bundle[2] = 0x42;
      bundle[3] = 0x4B;
      bundle[4] = 0x31;
      bundle[5] = 0x0A;
      expect(
        () => service.previewRestore(
          bundle: bundle,
          backupPassphrase: 'correct horse battery stapler',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.code,
            'code',
            'backup_truncated',
          ),
        ),
      );
    });

    test('rejette un schema_version trop récent dans le manifest', () async {
      // Manifest forge un schema_version=999 (futur format de bundle).
      final archive = Archive();
      final manifest = utf8.encode(
        jsonEncode({
          'kind': 'health_tech_full_backup',
          'app_version': '999.0.0+1',
          'schema_version': 999,
          'created_at': '2026-05-10T00:00:00.000Z',
        }),
      );
      archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
      final vault = utf8.encode(jsonEncode(<String, String>{}));
      archive.addFile(ArchiveFile('vault.json', vault.length, vault));
      final dbBytes = Uint8List.fromList([1, 2, 3]);
      archive.addFile(ArchiveFile('db/health.db', dbBytes.length, dbBytes));
      final innerZip = Uint8List.fromList(ZipEncoder().encode(archive));

      final bundle = await _forgeBundle(
        passphrase: 'correct horse battery stapler',
        innerZip: innerZip,
      );
      expect(
        () => service.previewRestore(
          bundle: bundle,
          backupPassphrase: 'correct horse battery stapler',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.code,
            'code',
            'backup_schema_unsupported',
          ),
        ),
      );
    });

    test('CONTRAT — maxSupportedDbUserVersion suit HealthDb.schemaVersion', () {
      // Garde-fou structurel (audit v1.6.0 G1 / F13). Si quelqu'un
      // bumpe `HealthDb.schemaVersion` sans bumper aussi
      // `BackupService._maxSupportedDbUserVersion`, ce test casse
      // AVANT que la nouvelle release sorte — et un user ne perd pas
      // sa capacité à restaurer son `.htbk` (régression historique
      // v1.5.0 → v1.5.4).
      final db = HealthDb.forTesting();
      addTearDown(db.close);
      expect(
        BackupService.maxSupportedDbUserVersionForTesting,
        equals(db.schemaVersion),
        reason:
            'BackupService._maxSupportedDbUserVersion DOIT être bumpé '
            'en parallèle de HealthDb.schemaVersion — sinon les .htbk '
            'produits par cette release ne sont pas restaurables.',
      );
    });

    test('rejette un db_user_version trop récent', () async {
      final archive = Archive();
      final manifest = utf8.encode(
        jsonEncode({
          'kind': 'health_tech_full_backup',
          'app_version': '2.0.0+1',
          'schema_version': 1,
          'db_user_version': 99,
          'created_at': '2026-05-10T00:00:00.000Z',
        }),
      );
      archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
      final vault = utf8.encode(jsonEncode(<String, String>{}));
      archive.addFile(ArchiveFile('vault.json', vault.length, vault));
      final dbBytes = Uint8List.fromList([1, 2, 3]);
      archive.addFile(ArchiveFile('db/health.db', dbBytes.length, dbBytes));
      final innerZip = Uint8List.fromList(ZipEncoder().encode(archive));

      final bundle = await _forgeBundle(
        passphrase: 'correct horse battery stapler',
        innerZip: innerZip,
      );
      expect(
        () => service.previewRestore(
          bundle: bundle,
          backupPassphrase: 'correct horse battery stapler',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.code,
            'code',
            'backup_db_version_too_new',
          ),
        ),
      );
    });
  });
}
