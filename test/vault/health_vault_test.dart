import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/data/vault/health_vault.dart';

/// Minimal in-memory FlutterSecureStorage stand-in. Lets us drive the vault
/// without standing up the full plugin platform channels in unit tests.
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
  }) async =>
      _store[key];

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
  }) async =>
      _store.remove(key);

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store.containsKey(key);

  // The remaining methods aren't exercised by the vault — but they must be
  // declared because [FlutterSecureStorage] is concrete (not an interface).
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'unsupported in tests: ${invocation.memberName}',
    );
  }
}

void main() {
  group('HealthVault', () {
    test('setup → unlock cycle reuses the wrapped VEK', () async {
      final storage = _MemoryStorage();
      final v1 = HealthVault(secureStorage: storage);
      expect(await v1.isInitialised(), isFalse);

      await v1.setupWithPassphrase('correct horse battery staple');
      expect(v1.isUnlocked, isTrue);
      final hex1 = v1.sqlCipherPassphrase();
      expect(hex1, matches(RegExp(r'^[0-9a-f]{64}$')));
      v1.lock();

      // Same passphrase, fresh vault instance — must unwrap the same VEK.
      final v2 = HealthVault(secureStorage: storage);
      expect(await v2.isInitialised(), isTrue);
      expect(await v2.unlockWithPassphrase('correct horse battery staple'), isTrue);
      expect(v2.sqlCipherPassphrase(), equals(hex1));
    });

    test('rejects wrong passphrase without unlocking', () async {
      final storage = _MemoryStorage();
      final v = HealthVault(secureStorage: storage);
      await v.setupWithPassphrase('right one');
      v.lock();

      expect(await v.unlockWithPassphrase('wrong one'), isFalse);
      expect(v.isUnlocked, isFalse);
      // The vault must still accept the right passphrase afterwards.
      expect(await v.unlockWithPassphrase('right one'), isTrue);
    });

    test('setup throws when called on an already-initialised vault',
        () async {
      final storage = _MemoryStorage();
      final v = HealthVault(secureStorage: storage);
      await v.setupWithPassphrase('first');
      expect(
        () => v.setupWithPassphrase('second'),
        throwsStateError,
      );
    });

    test('destroy() wipes both memory and secure storage', () async {
      final storage = _MemoryStorage();
      final v = HealthVault(secureStorage: storage);
      await v.setupWithPassphrase('temp');
      await v.destroy();
      expect(v.isUnlocked, isFalse);
      expect(await v.isInitialised(), isFalse);
    });

    test('sqlCipherPassphrase requires an unlocked state', () {
      final v = HealthVault(secureStorage: _MemoryStorage());
      expect(v.sqlCipherPassphrase, throwsStateError);
    });
  });
}
