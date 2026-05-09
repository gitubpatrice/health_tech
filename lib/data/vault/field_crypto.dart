import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-256-GCM per-field encryption.
///
/// Layout of every produced ciphertext blob (base64):
///   [version:1][nonce:12][cipherText:N][mac:16]
///
/// `version` lets us evolve the algorithm without breaking older rows.
/// The DB-level SQLCipher already protects everything at rest; this layer adds
/// defence in depth so a partial dump (e.g. SQL view export, RAM dump) cannot
/// read sensitive columns without the runtime master key.
class FieldCrypto {
  FieldCrypto(this._key)
      : assert(_key.length == 32, 'Master key must be 32 bytes');

  static const int _version = 1;
  static const int _nonceLen = 12;
  static const int _macLen = 16;

  final Uint8List _key;
  final AesGcm _aead = AesGcm.with256bits();

  Future<String> encryptString(String plaintext) async {
    if (plaintext.isEmpty) return '';
    final secretKey = SecretKey(_key);
    final nonce = _aead.newNonce();
    final box = await _aead.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
    );
    final cipherLen = box.cipherText.length;
    final out = Uint8List(1 + _nonceLen + cipherLen + _macLen);
    out[0] = _version;
    out.setRange(1, 1 + _nonceLen, nonce);
    out.setRange(1 + _nonceLen, 1 + _nonceLen + cipherLen, box.cipherText);
    out.setRange(1 + _nonceLen + cipherLen, out.length, box.mac.bytes);
    return base64Encode(out);
  }

  Future<String> decryptString(String blob) async {
    if (blob.isEmpty) return '';
    final bytes = base64Decode(blob);
    if (bytes.isEmpty || bytes[0] != _version) {
      throw const FormatException('Unsupported field crypto version');
    }
    if (bytes.length < 1 + _nonceLen + _macLen) {
      throw const FormatException('Field crypto blob truncated');
    }
    final nonce = bytes.sublist(1, 1 + _nonceLen);
    final cipher =
        bytes.sublist(1 + _nonceLen, bytes.length - _macLen);
    final mac = Mac(bytes.sublist(bytes.length - _macLen));
    final box = SecretBox(cipher, nonce: nonce, mac: mac);
    final clear = await _aead.decrypt(box, secretKey: SecretKey(_key));
    return utf8.decode(clear);
  }

  /// Encrypts arbitrary binary data and returns a self-describing blob:
  ///   `[version:1][nonce:12][cipherText:N][mac:16]`
  ///
  /// Designed for file storage on disk (no base64 wrapping). Input bytes are
  /// not modified; caller is responsible for wiping plaintext sources.
  Future<Uint8List> encryptBytes(Uint8List plaintext) async {
    final secretKey = SecretKey(_key);
    final nonce = _aead.newNonce();
    final box = await _aead.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );
    final cipherLen = box.cipherText.length;
    final out = Uint8List(1 + _nonceLen + cipherLen + _macLen);
    out[0] = _version;
    out.setRange(1, 1 + _nonceLen, nonce);
    out.setRange(1 + _nonceLen, 1 + _nonceLen + cipherLen, box.cipherText);
    out.setRange(1 + _nonceLen + cipherLen, out.length, box.mac.bytes);
    return out;
  }

  Future<Uint8List> decryptBytes(Uint8List blob) async {
    if (blob.isEmpty || blob[0] != _version) {
      throw const FormatException('Unsupported binary crypto version');
    }
    if (blob.length < 1 + _nonceLen + _macLen) {
      throw const FormatException('Binary crypto blob truncated');
    }
    final nonce = blob.sublist(1, 1 + _nonceLen);
    final cipher = blob.sublist(1 + _nonceLen, blob.length - _macLen);
    final mac = Mac(blob.sublist(blob.length - _macLen));
    final box = SecretBox(cipher, nonce: nonce, mac: mac);
    final clear = await _aead.decrypt(box, secretKey: SecretKey(_key));
    return Uint8List.fromList(clear);
  }

  /// Best-effort wipe of the in-memory key. The Dart VM gives no guarantee,
  /// but zeroing the visible buffer reduces the window.
  void dispose() {
    _key.fillRange(0, _key.length, 0);
  }
}
