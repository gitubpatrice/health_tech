import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/data/vault/field_crypto.dart';

void main() {
  group('FieldCrypto bytes API', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));

    test('round-trip preserves random binary payloads', () async {
      final crypto = FieldCrypto(key);
      final rng = Random(42);
      final payload = Uint8List.fromList(
        List<int>.generate(8192, (_) => rng.nextInt(256)),
      );
      final blob = await crypto.encryptBytes(payload);
      final decoded = await crypto.decryptBytes(blob);
      expect(decoded, equals(payload));
    });

    test('two encryptions of same bytes yield distinct blobs', () async {
      final crypto = FieldCrypto(key);
      final payload = Uint8List.fromList(List.filled(64, 0x42));
      final a = await crypto.encryptBytes(payload);
      final b = await crypto.encryptBytes(payload);
      expect(a, isNot(equals(b)));
    });

    test('rejects truncated blob', () async {
      final crypto = FieldCrypto(key);
      expect(
        () => crypto.decryptBytes(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unsupported version byte', () async {
      final crypto = FieldCrypto(key);
      final payload = Uint8List.fromList(List.filled(32, 0));
      final blob = await crypto.encryptBytes(payload);
      blob[0] = 0xFF;
      expect(() => crypto.decryptBytes(blob), throwsA(isA<FormatException>()));
    });
  });
}
