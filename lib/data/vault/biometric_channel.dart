import 'dart:convert';

import 'package:flutter/services.dart';

/// Thin Dart wrapper around `BiometricBridge.kt`.
///
/// The Keystore key it manipulates lives in Android's secure hardware (StrongBox
/// when available). This class never sees raw key material — it only ferries
/// VEK plaintext / ciphertext across the channel for wrap & unwrap.
class BiometricChannel {
  const BiometricChannel();

  static const _channel = MethodChannel('com.filestech.health_tech/biometric');

  Future<bool> isAvailable() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable');
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Bridge is Android-only; on other platforms (tests, desktop) the
      // channel resolves to a missing plugin.
      return false;
    }
  }

  /// Wraps the given plaintext under a fresh Keystore-bound AES-GCM key.
  /// Shows the BiometricPrompt because the key is created with
  /// `setUserAuthenticationRequired(true)` — that flag covers BOTH encrypt
  /// and decrypt operations, so wrapping the VEK at enable-time goes
  /// through the same prompt the user will see at every unlock.
  Future<BiometricWrap> wrap({
    required Uint8List plaintext,
    required String title,
    required String subtitle,
    required String negativeButton,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>('wrap', {
        'plaintext': base64Encode(plaintext),
        'title': title,
        'subtitle': subtitle,
        'negativeButton': negativeButton,
      });
      if (res == null) {
        throw const BiometricFailure('wrap_failed');
      }
      return BiometricWrap(
        iv: base64Decode(res['iv'] as String),
        ciphertext: base64Decode(res['ciphertext'] as String),
      );
    } on PlatformException catch (e) {
      throw BiometricFailure(e.code);
    }
  }

  /// Shows the system biometric prompt; on success the bound Cipher decrypts
  /// the ciphertext and returns the recovered plaintext. Throws
  /// [BiometricFailure] on cancel / no-key / hardware error.
  Future<Uint8List> unwrap({
    required Uint8List iv,
    required Uint8List ciphertext,
    required String title,
    required String subtitle,
    required String negativeButton,
  }) async {
    try {
      final res = await _channel.invokeMethod<String>('unwrap', {
        'iv': base64Encode(iv),
        'ciphertext': base64Encode(ciphertext),
        'title': title,
        'subtitle': subtitle,
        'negativeButton': negativeButton,
      });
      if (res == null) {
        throw const BiometricFailure('unwrap_returned_null');
      }
      return base64Decode(res);
    } on PlatformException catch (e) {
      throw BiometricFailure(e.code);
    }
  }

  Future<void> delete() async {
    // Delete is best-effort: a stale entry will be overwritten on the next
    // wrap() call. We swallow EVERY failure (PlatformException,
    // MissingPluginException, and even pre-binding errors raised in unit
    // tests) so vault-level operations like `destroy()` keep their
    // strong cleanup contract.
    try {
      await _channel.invokeMethod<void>('delete');
    } on Object {
      // ignore — see method comment.
    }
  }
}

class BiometricWrap {
  const BiometricWrap({required this.iv, required this.ciphertext});
  final Uint8List iv;
  final Uint8List ciphertext;
}

class BiometricFailure implements Exception {
  const BiometricFailure(this.code);
  final String code;
  bool get userCancelled => code == 'auth_error';
  bool get keyMissing => code == 'no_key';
  @override
  String toString() => 'BiometricFailure($code)';
}
