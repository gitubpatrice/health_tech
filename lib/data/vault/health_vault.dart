import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
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

  /// Compteur d'échecs consécutifs + timestamp du dernier échec, persistés
  /// dans EncryptedSharedPreferences (donc résistent à un kill d'app mais
  /// PAS à un reset du device — acceptable car un attaquant qui factory-reset
  /// efface aussi le wrapped VEK et n'a plus rien à brute-force).
  static const _kFailCount = 'health_vault.fail_count_v1';
  static const _kFailAt = 'health_vault.fail_at_ms_v1';

  /// Timestamp du dernier verrouillage. Utilisé par le Lock screen pour
  /// décider si la biométrie est autorisée comme raccourci (re-unlock à
  /// chaud rapide) ou si la passphrase est forcée (cold-start, ou délai
  /// d'inactivité long > 1h). Implémente le pattern hybride 1Password /
  /// Bitwarden : la passphrase reste le facteur fort canonique, la
  /// biométrie n'est qu'un raccourci dans les fenêtres de session active.
  static const _kLastLockedAt = 'health_vault.last_locked_at_ms_v1';

  /// Identifier for the active Argon2id backend (`native` when
  /// `cryptography_flutter` is wired, `dart` otherwise).
  /// Identifiant du backend Argon2id réellement actif. Avant ce fix, la
  /// valeur était la constante `'flutter'`, ce qui rendait
  /// [_maybeRecalibrate] inopérant : si on basculait un jour vers
  /// `cryptography_flutter` natif (Argon2id ~10× plus rapide via JNI
  /// BoringSSL), le tag stocké restait identique → pas de recalibration
  /// → unlock 75ms au lieu de 750ms → budget brute-force divisé par 10.
  ///
  /// Détection :
  ///   - On vérifie `Cryptography.instance` à chaud — si ça retourne
  ///     une instance de `FlutterCryptography`, le natif est routé.
  ///   - On versionne le tag (`-v2`) pour que le bump d'app force une
  ///     recalibration sur les coffres existants.
  static String get _currentBackend {
    final inst = Cryptography.instance;
    final isNative = inst.runtimeType.toString().contains('Flutter');
    return isNative ? 'native-v2' : 'dart-v2';
  }

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
    // Backoff anti-bruteforce on-device : si le user a échoué N fois
    // récemment, refuse de dériver Argon2id avant que le délai ne soit
    // écoulé. Sans ce garde-fou, un attaquant ADB sur device perdu peut
    // tenter ~115k passphrases/jour (Argon2id 750ms/tentative).
    final remaining = await _lockoutRemainingSeconds();
    if (remaining > 0) {
      throw VaultLockedOutError(remaining);
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
      // Reset des compteurs d'échec sur succès.
      await _storage.delete(key: _kFailCount);
      await _storage.delete(key: _kFailAt);
      unawaited(_maybeRecalibrate(salt: base64Decode(saltB64)));
      return true;
    } on SecretBoxAuthenticationError {
      // Vraie tentative ratée : passphrase incorrecte. On incrémente le
      // compteur d'échecs (déclenche le backoff exponentiel).
      await _registerFailedAttempt();
      return false;
    } on FormatException {
      // Wrapped VEK corrompu / tronqué (malware ayant manipulé l'Encrypted
      // SharedPreferences). On NE compte PAS comme un échec de passphrase :
      // l'utilisateur légitime ne doit pas être lockout pour un état DB
      // cassé qu'il n'a pas causé. On rethrow pour que l'UI affiche un
      // message d'erreur générique distinct du "wrong passphrase".
      rethrow;
    } finally {
      masterKey.fillRange(0, masterKey.length, 0);
    }
  }

  /// Calcule le nombre de secondes restantes avant qu'un nouveau unlock
  /// puisse être tenté. 0 = pas de lockout actif.
  ///
  /// Le `lastFailedAt` stocké est comparé au max(stored, now) pour
  /// résister à un rollback du clock système (cf. notes Pass Tech /
  /// Notes Tech : un attaquant root pourrait sinon backdater le clock
  /// pour court-circuiter le délai).
  Future<int> _lockoutRemainingSeconds() async {
    final countStr = await _storage.read(key: _kFailCount);
    final atStr = await _storage.read(key: _kFailAt);
    if (countStr == null || atStr == null) return 0;
    final count = int.tryParse(countStr) ?? 0;
    final at = int.tryParse(atStr) ?? 0;
    final delaySec = _backoffSecondsFor(count);
    if (delaySec == 0) return 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final unlockAtMs = at + delaySec * 1000;
    final remainingMs = unlockAtMs - nowMs;
    if (remainingMs <= 0) return 0;
    return (remainingMs / 1000).ceil();
  }

  /// Backoff exponentiel pas trop agressif : aucun délai pour les 2
  /// premiers échecs (la phrase secrète est vraiment longue, l'humain se
  /// trompe au clavier mobile), puis 10s / 60s / 5min / 1h. À 10+ échecs,
  /// l'attaquant cumule déjà > 1h pour 1 essai = brute-force impossible.
  static int _backoffSecondsFor(int failCount) {
    if (failCount < 3) return 0;
    if (failCount < 5) return 10;
    if (failCount < 8) return 60;
    if (failCount < 10) return 300;
    return 3600;
  }

  Future<void> _registerFailedAttempt() async {
    final prevStr = await _storage.read(key: _kFailCount);
    final prev = int.tryParse(prevStr ?? '') ?? 0;
    final next = prev + 1;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Anti rollback clock : on garde le max entre le timestamp en mémoire
    // et `now`. Un attaquant root qui set le clock dans le passé ne peut
    // pas raccourcir le délai en attendant.
    final atStr = await _storage.read(key: _kFailAt);
    final prevAt = int.tryParse(atStr ?? '') ?? 0;
    final at = nowMs > prevAt ? nowMs : prevAt;
    await _storage.write(key: _kFailCount, value: '$next');
    await _storage.write(key: _kFailAt, value: '$at');
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

  /// Lit le timestamp (epoch ms) du dernier verrouillage. `null` = jamais
  /// verrouillé sur ce device (cold-start après install, ou destroy()).
  /// Le Lock screen utilise ce timestamp pour détecter un cold-start
  /// (passphrase forcée) et un éventuel rollback du clock système
  /// (anti-rollback : delta négatif ⇒ passphrase forcée).
  Future<int?> lastLockedAtMs() async {
    final s = await _storage.read(key: _kLastLockedAt);
    if (s == null) return null;
    return int.tryParse(s);
  }

  void lock() {
    _crypto?.dispose();
    _crypto = null;
    // Stockage best-effort du timestamp de lock — tracked uniquement pour
    // l'UX du Lock screen (autorisation biométrie). Si le write échoue,
    // le défaut côté Lock screen est de FORCER la passphrase, donc
    // fail-closed.
    unawaited(
      _storage.write(
        key: _kLastLockedAt,
        value: '${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
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
    await _storage.delete(key: _kFailCount);
    await _storage.delete(key: _kFailAt);
    await _storage.delete(key: _kLastLockedAt);
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
  /// in-memory VEK with a fresh Keystore-bound key. The wrap requires
  /// going through the BiometricPrompt (the key is provisioned with
  /// `setUserAuthenticationRequired(true)`, so even the encrypt step
  /// needs an authenticated cipher), hence the prompt strings.
  /// **Durcissement audit v1.3.1 H6** : enable/disable passent maintenant
  /// par le mutex `_serialize` qui sérialise déjà setup/unlock/lock.
  /// Sans cela, un toggle ON-OFF-ON rapide (UI accessibility ou pression
  /// nerveuse de l'utilisateur) pouvait interleaver les writes
  /// FlutterSecureStorage et empiler deux BiometricPrompt côté Kotlin
  /// (IllegalStateException + blob orphelin).
  Future<void> enableBiometric({
    required String title,
    required String subtitle,
    required String negativeButton,
  }) => _serialize(() async {
    final vek = _vek;
    if (vek == null) throw const VaultLockedError();
    final wrap = await _biometric.wrap(
      plaintext: Uint8List.fromList(vek),
      title: title,
      subtitle: subtitle,
      negativeButton: negativeButton,
    );
    await _storage.write(key: _kBioIv, value: base64Encode(wrap.iv));
    await _storage.write(
      key: _kBioCipher,
      value: base64Encode(wrap.ciphertext),
    );
  });

  /// Drop the biometric-wrapped VEK and the underlying Keystore key.
  Future<void> disableBiometric() => _serialize(() async {
    await _storage.delete(key: _kBioIv);
    await _storage.delete(key: _kBioCipher);
    await _biometric.delete();
  });

  /// Show the BiometricPrompt and, on success, recover the VEK without
  /// asking for the passphrase. Throws [BiometricFailure] if the user
  /// cancels or the hardware refuses; throws [VaultNotInitialisedError]
  /// if biometric was never enabled.
  Future<bool> unlockWithBiometric({
    required String title,
    required String subtitle,
    required String negativeButton,
  }) => _serialize(() async {
    // Si déjà déverrouillé (cas race auto-prompt + tap manuel), on wipe
    // l'ancien matériel avant d'écrire le nouveau pour ne pas fuiter une
    // ancienne copie du VEK en mémoire jusqu'au prochain GC.
    if (_vek != null) {
      _crypto?.dispose();
      _vek!.fillRange(0, _vek!.length, 0);
      _vek = null;
      _crypto = null;
    }
    final ivB64 = await _storage.read(key: _kBioIv);
    final ctB64 = await _storage.read(key: _kBioCipher);
    if (ivB64 == null || ctB64 == null) {
      throw const VaultNotInitialisedError();
    }
    final iv = base64Decode(ivB64);
    if (iv.length != 12) {
      // IV corrompu (n'a jamais dû arriver via le bridge mais defense
      // in depth). Désactive la biométrie pour forcer un setup propre.
      await disableBiometric();
      return false;
    }
    Uint8List vek;
    try {
      vek = await _biometric.unwrap(
        iv: iv,
        ciphertext: base64Decode(ctB64),
        title: title,
        subtitle: subtitle,
        negativeButton: negativeButton,
      );
    } on BiometricFailure catch (e) {
      // L'enrollment biométrique a changé ou la clé est sortie du
      // Keystore : on nettoie côté vault pour qu'un futur prompt ne
      // tape pas indéfiniment dans un blob orphelin.
      if (e.keyInvalidated) {
        await disableBiometric();
      }
      rethrow;
    }
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
    // 64 MiB / 3 iter Argon2id is ~750 ms on S24 FE and ~1.5 s on S9 — too
    // long to run on the UI isolate without freezing the lock screen
    // pinwheel. Push it off to a background isolate via `compute()`.
    //
    // **Audit M9** : on encode la passphrase en UTF-8 LOCALEMENT (donc
    // `bytes` peut être wipé après dérivation), et on transmet le
    // Uint8List wipable. Le `String passphrase` lui-même reste en
    // mémoire (immuable Dart), mais on minimise la fenêtre où une
    // copie supplémentaire (la version isolate) vit.
    final pBytes = Uint8List.fromList(utf8.encode(passphrase));
    try {
      return await compute<_KdfInput, Uint8List>(
        _deriveMasterKeyIsolate,
        _KdfInput(
          passphraseBytes: pBytes,
          salt: salt,
          memoryKb: memoryKb,
          iterations: iterations,
          parallelism: parallelism,
        ),
      );
    } finally {
      // (audit code M5) Le worker isolate wipe SA copie ; côté main
      // isolate on wipe la nôtre, succès ou throw — y compris si
      // Argon2id casse sur low-memory. Best-effort : Dart String reste
      // immuable, mais on supprime la fenêtre Uint8List.
      pBytes.fillRange(0, pBytes.length, 0);
    }
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

/// Top-level inputs for [_deriveMasterKeyIsolate]. Must be a top-level (not
/// a private inner) class because `compute()` sends the value across an
/// isolate boundary and therefore needs trivially-serialisable data.
///
/// **Audit M9** : on transporte la passphrase sous forme `Uint8List`
/// (UTF-8 encoded) au lieu d'un `String`. Bénéfice : le caller peut
/// `fillRange(0)` ses bytes après envoi, et le receiver wipe ses bytes
/// après extraction. Réduit la fenêtre RAM où une passphrase legacy
/// vit en clair (Dart String est immuable et GC-only).
class _KdfInput {
  const _KdfInput({
    required this.passphraseBytes,
    required this.salt,
    required this.memoryKb,
    required this.iterations,
    required this.parallelism,
  });
  final Uint8List passphraseBytes;
  final Uint8List salt;
  final int memoryKb;
  final int iterations;
  final int parallelism;
}

/// Worker entry point: must be a top-level function so `compute()` can
/// resolve it inside the spawned isolate. Returns the 32-byte master key
/// derived from the passphrase + salt under Argon2id.
Future<Uint8List> _deriveMasterKeyIsolate(_KdfInput input) async {
  final algo = Argon2id(
    memory: input.memoryKb,
    parallelism: input.parallelism,
    iterations: input.iterations,
    hashLength: 32,
  );
  final key = await algo.deriveKey(
    secretKey: SecretKey(input.passphraseBytes),
    nonce: input.salt,
  );
  final bytes = await key.extractBytes();
  // Wipe la copie côté isolate après dérivation. Le caller wipe la sienne
  // de son côté (on ne peut pas faire mieux avec Dart).
  input.passphraseBytes.fillRange(0, input.passphraseBytes.length, 0);
  return Uint8List.fromList(bytes);
}
