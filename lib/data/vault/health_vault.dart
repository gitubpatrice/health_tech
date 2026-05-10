import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/errors.dart';
import 'biometric_channel.dart';
import 'field_crypto.dart';

/// Single source of truth for the master key lifecycle.
///
/// Lifecycle:
///   1. First launch  -> [setupWithPassphrase] derives a master key from the
///      user's passphrase via Argon2id, generates a random Vault Encryption
///      Key (VEK), wraps the VEK with the master key, and persists the
///      wrapped blob + Argon2id parameters in [FlutterSecureStorage]
///      (Android Keystore-backed, hardware when available).
///   2. Each unlock -> [unlockWithPassphrase] re-derives the master key,
///      unwraps the VEK, and instantiates the [FieldCrypto] used everywhere.
///   3. [lock] wipes the VEK from memory.
///
/// Why two keys (master + VEK):
///   - Lets the user change their passphrase without re-encrypting every
///     ciphertext in the database (only the wrapped VEK needs rewriting).
///   - VEK is uniformly random (better than a passphrase-derived key for AEAD).
class HealthVault {
  HealthVault({
    FlutterSecureStorage? secureStorage,
    BiometricChannel? biometric,
  }) : _storage =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(
               encryptedSharedPreferences: true,
               resetOnError: false,
             ),
           ),
       _biometric = biometric ?? const BiometricChannel();

  static const _kWrappedVek = 'health_vault.wrapped_vek_v1';
  static const _kKdfSalt = 'health_vault.kdf_salt_v1';
  static const _kKdfMemory = 'health_vault.kdf_memory_v1';
  static const _kKdfIterations = 'health_vault.kdf_iterations_v1';
  static const _kKdfParallelism = 'health_vault.kdf_parallelism_v1';

  /// Backend tag persisted alongside the KDF parameters. When the user
  /// upgrades the app and the underlying Argon2id implementation switches
  /// (pure Dart → native JNI), unlock takes a fraction of the previous
  /// time which would weaken the brute-force budget. We re-calibrate
  /// lazily on the next successful unlock when this tag changes.
  static const _kKdfBackend = 'health_vault.kdf_backend_v1';

  /// Biometric-wrapped VEK + IV. Persisted only after the user opts in via
  /// [enableBiometric] while the vault is unlocked.
  static const _kBioIv = 'health_vault.bio_iv_v1';
  static const _kBioCipher = 'health_vault.bio_ct_v1';

  /// Identifier for the active Argon2id backend (`native` when
  /// `cryptography_flutter` is wired, `dart` otherwise).
  static String get _currentBackend => 'flutter';

  // Argon2id default cost — tuned for mid-range Android phones (Galaxy S9 era).
  // Adjust upward as devices get faster.
  static const int _defaultMemoryKb = 64 * 1024; // 64 MiB
  static const int _defaultIterations = 3;
  static const int _defaultParallelism = 1;

  static const int _vekLen = 32;
  static const int _saltLen = 16;
  static const int _wrapNonceLen = 12;
  static const int _macLen = 16;

  final FlutterSecureStorage _storage;
  final BiometricChannel _biometric;
  final AesGcm _wrap = AesGcm.with256bits();

  Uint8List? _vek;
  FieldCrypto? _crypto;

  /// Mutex preventing concurrent setup/unlock/lock operations from
  /// interleaving in unsafe ways (a double-tap on "Unlock" would otherwise
  /// race two derivations and leave `_vek` and `_crypto` desynchronised —
  /// `isUnlocked == true` but `crypto` raising `StateError`).
  Future<void>? _gate;

  bool get isUnlocked => _vek != null;

  /// True when the vault has been initialised at least once on this device.
  Future<bool> isInitialised() async =>
      (await _storage.read(key: _kWrappedVek)) != null;

  FieldCrypto get crypto {
    final c = _crypto;
    if (c == null) {
      throw const VaultLockedError();
    }
    return c;
  }

  /// First-time setup: generate a fresh VEK, wrap it under the passphrase.
  ///
  /// Throws [StateError] if the vault is already initialised; callers must
  /// reset explicitly to avoid accidental data loss.
  Future<T> _serialize<T>(Future<T> Function() body) async {
    final previous = _gate;
    final completer = Completer<void>();
    _gate = completer.future;
    try {
      if (previous != null) {
        await previous;
      }
      return await body();
    } finally {
      completer.complete();
    }
  }

  Future<void> setupWithPassphrase(String passphrase) =>
      _serialize(() => _setupLocked(passphrase));

  Future<void> _setupLocked(String passphrase) async {
    if (await isInitialised()) {
      throw const VaultAlreadyInitialisedError();
    }
    final salt = _randomBytes(_saltLen);
    final iterations = await _calibrateIterations(salt: salt);
    final masterKey = await _deriveMasterKey(
      passphrase: passphrase,
      salt: salt,
      memoryKb: _defaultMemoryKb,
      iterations: iterations,
      parallelism: _defaultParallelism,
    );
    final vek = _randomBytes(_vekLen);
    final wrapped = await _wrapVek(vek, masterKey);

    await _storage.write(key: _kWrappedVek, value: base64Encode(wrapped));
    await _storage.write(key: _kKdfSalt, value: base64Encode(salt));
    await _storage.write(key: _kKdfMemory, value: '$_defaultMemoryKb');
    await _storage.write(key: _kKdfIterations, value: '$iterations');
    await _storage.write(key: _kKdfParallelism, value: '$_defaultParallelism');
    await _storage.write(key: _kKdfBackend, value: _currentBackend);

    masterKey.fillRange(0, masterKey.length, 0);
    _vek = vek;
    _crypto = FieldCrypto(Uint8List.fromList(vek));
  }

  /// Background task: when the active backend differs from the one we
  /// calibrated against, re-derive the iteration count so unlock keeps a
  /// stable wall-clock cost (and brute-force budget). Persists the new
  /// values + the backend tag.
  Future<void> _maybeRecalibrate({required Uint8List salt}) async {
    try {
      final stored = await _storage.read(key: _kKdfBackend);
      if (stored == _currentBackend) return;
      final iterations = await _calibrateIterations(salt: salt);
      await _storage.write(key: _kKdfIterations, value: '$iterations');
      await _storage.write(key: _kKdfBackend, value: _currentBackend);
    } on Object {
      // Best-effort only.
    }
  }

  /// Calibrates Argon2id iterations to target ~750 ms on the current device.
  /// Starts at the configured default; if a single-iteration probe finishes
  /// faster than expected we keep more iterations, slower we keep fewer
  /// (with a hard floor of 2 iterations and ceiling of 6).
  Future<int> _calibrateIterations({
    required Uint8List salt,
    int targetMs = 750,
  }) async {
    final probeKey = utf8.encode('calibration-probe');
    final stopwatch = Stopwatch()..start();
    final probe = await Argon2id(
      memory: _defaultMemoryKb,
      parallelism: _defaultParallelism,
      iterations: 1,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(probeKey), nonce: salt);
    await probe.extractBytes();
    stopwatch.stop();
    final perIter = stopwatch.elapsedMilliseconds.clamp(50, 4000);
    final estimated = (targetMs / perIter).round();
    return estimated.clamp(2, 6);
  }

  /// Returns true on success, false if the passphrase was wrong.
  Future<bool> unlockWithPassphrase(String passphrase) =>
      _serialize(() => _unlockLocked(passphrase));

  Future<bool> _unlockLocked(String passphrase) async {
    final wrappedB64 = await _storage.read(key: _kWrappedVek);
    final saltB64 = await _storage.read(key: _kKdfSalt);
    if (wrappedB64 == null || saltB64 == null) {
      throw const VaultNotInitialisedError();
    }
    final memoryKb = int.parse(
      await _storage.read(key: _kKdfMemory) ?? '$_defaultMemoryKb',
    );
    final iterations = int.parse(
      await _storage.read(key: _kKdfIterations) ?? '$_defaultIterations',
    );
    final parallelism = int.parse(
      await _storage.read(key: _kKdfParallelism) ?? '$_defaultParallelism',
    );

    final masterKey = await _deriveMasterKey(
      passphrase: passphrase,
      salt: base64Decode(saltB64),
      memoryKb: memoryKb,
      iterations: iterations,
      parallelism: parallelism,
    );
    try {
      final vek = await _unwrapVek(base64Decode(wrappedB64), masterKey);
      _vek = vek;
      _crypto = FieldCrypto(Uint8List.fromList(vek));
      // Lazy re-calibration: if the Argon2id backend changed since last
      // setup (e.g. native plugin enabled), bump iterations to keep the
      // unlock cost in the same wall-clock target. Best-effort, errors are
      // swallowed so a calibration hiccup never blocks a valid unlock.
      unawaited(_maybeRecalibrate(salt: base64Decode(saltB64)));
      return true;
    } on SecretBoxAuthenticationError {
      return false;
    } finally {
      masterKey.fillRange(0, masterKey.length, 0);
    }
  }

  /// Returns a defensive copy of the raw 32-byte VEK. Used to key the
  /// database without ever creating a Dart String that holds the VEK
  /// outside of the SQLCipher setup callback.
  ///
  /// The caller is expected to wipe the returned buffer when done.
  Uint8List sqlCipherKeyBytes() {
    final vek = _vek;
    if (vek == null) throw const VaultLockedError();
    return Uint8List.fromList(vek);
  }

  void lock() {
    _crypto?.dispose();
    _crypto = null;
    final v = _vek;
    if (v != null) {
      v.fillRange(0, v.length, 0);
      _vek = null;
    }
  }

  /// Wipes all vault material from secure storage AND from memory.
  /// Caller is responsible for wiping the underlying database files.
  Future<void> destroy() async {
    lock();
    await _storage.delete(key: _kWrappedVek);
    await _storage.delete(key: _kKdfSalt);
    await _storage.delete(key: _kKdfMemory);
    await _storage.delete(key: _kKdfIterations);
    await _storage.delete(key: _kKdfParallelism);
    await disableBiometric();
  }

  // -- Biometric unlock -----------------------------------------------------

  /// True iff the user has previously opted in and a biometric-wrapped VEK
  /// is currently persisted. Does NOT verify hardware availability — the
  /// caller should also consult [biometricAvailable] before showing the UI.
  Future<bool> isBiometricEnrolled() async =>
      (await _storage.read(key: _kBioIv)) != null &&
      (await _storage.read(key: _kBioCipher)) != null;

  /// Hardware + enrollment check. Independent of [isBiometricEnrolled].
  Future<bool> biometricAvailable() => _biometric.isAvailable();

  /// Enable biometric unlock. The vault MUST be unlocked: we wrap the
  /// in-memory VEK with a fresh Keystore-bound key. After this call the
  /// next launch can offer the biometric prompt as a passphrase shortcut.
  Future<void> enableBiometric() async {
    final vek = _vek;
    if (vek == null) throw const VaultLockedError();
    final wrap = await _biometric.wrap(Uint8List.fromList(vek));
    await _storage.write(key: _kBioIv, value: base64Encode(wrap.iv));
    await _storage.write(
      key: _kBioCipher,
      value: base64Encode(wrap.ciphertext),
    );
  }

  /// Drop the biometric-wrapped VEK and the underlying Keystore key.
  Future<void> disableBiometric() async {
    await _storage.delete(key: _kBioIv);
    await _storage.delete(key: _kBioCipher);
    await _biometric.delete();
  }

  /// Show the BiometricPrompt and, on success, recover the VEK without
  /// asking for the passphrase. Throws [BiometricFailure] if the user
  /// cancels or the hardware refuses; throws [VaultNotInitialisedError]
  /// if biometric was never enabled.
  Future<bool> unlockWithBiometric({
    required String title,
    required String subtitle,
    required String negativeButton,
  }) => _serialize(() async {
    final ivB64 = await _storage.read(key: _kBioIv);
    final ctB64 = await _storage.read(key: _kBioCipher);
    if (ivB64 == null || ctB64 == null) {
      throw const VaultNotInitialisedError();
    }
    final vek = await _biometric.unwrap(
      iv: base64Decode(ivB64),
      ciphertext: base64Decode(ctB64),
      title: title,
      subtitle: subtitle,
      negativeButton: negativeButton,
    );
    if (vek.length != _vekLen) {
      // Corrupted blob — fail closed and force passphrase re-entry.
      await disableBiometric();
      return false;
    }
    _vek = vek;
    _crypto = FieldCrypto(Uint8List.fromList(vek));
    return true;
  });

  Future<Uint8List> _deriveMasterKey({
    required String passphrase,
    required Uint8List salt,
    required int memoryKb,
    required int iterations,
    required int parallelism,
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

  Future<Uint8List> _wrapVek(Uint8List vek, Uint8List masterKey) async {
    final nonce = _wrap.newNonce();
    final box = await _wrap.encrypt(
      vek,
      secretKey: SecretKey(masterKey),
      nonce: nonce,
    );
    final out = Uint8List(_wrapNonceLen + box.cipherText.length + _macLen);
    out.setRange(0, _wrapNonceLen, nonce);
    out.setRange(
      _wrapNonceLen,
      _wrapNonceLen + box.cipherText.length,
      box.cipherText,
    );
    out.setRange(
      _wrapNonceLen + box.cipherText.length,
      out.length,
      box.mac.bytes,
    );
    return out;
  }

  Future<Uint8List> _unwrapVek(Uint8List wrapped, Uint8List masterKey) async {
    if (wrapped.length < _wrapNonceLen + _macLen) {
      throw const FormatException('Wrapped VEK truncated');
    }
    final nonce = wrapped.sublist(0, _wrapNonceLen);
    final cipher = wrapped.sublist(_wrapNonceLen, wrapped.length - _macLen);
    final mac = Mac(wrapped.sublist(wrapped.length - _macLen));
    final box = SecretBox(cipher, nonce: nonce, mac: mac);
    final clear = await _wrap.decrypt(box, secretKey: SecretKey(masterKey));
    return Uint8List.fromList(clear);
  }

  static final Random _rng = Random.secure();

  static Uint8List _randomBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _rng.nextInt(256);
    }
    return out;
  }
}
