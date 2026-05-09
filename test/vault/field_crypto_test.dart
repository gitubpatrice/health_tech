import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/data/vault/field_crypto.dart';

void main() {
  group('FieldCrypto', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));

    test('round-trip preserves utf-8 content', () async {
      final crypto = FieldCrypto(key);
      final blob = await crypto.encryptString('Hellô éà 🌿');
      expect(blob, isNotEmpty);
      expect(await crypto.decryptString(blob), 'Hellô éà 🌿');
    });

    test('empty input returns empty blob', () async {
      final crypto = FieldCrypto(key);
      expect(await crypto.encryptString(''), '');
      expect(await crypto.decryptString(''), '');
    });

    test('two encryptions of same text produce different blobs (nonce)',
        () async {
      final crypto = FieldCrypto(key);
      final a = await crypto.encryptString('same content');
      final b = await crypto.encryptString('same content');
      expect(a, isNot(equals(b)));
    });

    test('rejects truncated blob', () async {
      final crypto = FieldCrypto(key);
      expect(
        () => crypto.decryptString('AQ=='),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
