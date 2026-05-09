import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/utils/image_bounds.dart';

void main() {
  group('ImageBoundsProbe', () {
    test('rejects bytes shorter than 16', () {
      expect(ImageBoundsProbe.probe(Uint8List(4)), isNull);
    });

    test('reads PNG dimensions from IHDR', () {
      // PNG signature + length(13) + 'IHDR' + width=100 + height=200 + 5 trailing bytes
      final bytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
        0x00, 0x00, 0x00, 0x0D, // IHDR length
        0x49, 0x48, 0x44, 0x52, // 'IHDR'
        0x00, 0x00, 0x00, 0x64, // width = 100
        0x00, 0x00, 0x00, 0xC8, // height = 200
        0x08, 0x02, 0x00, 0x00, 0x00, // depth, color, etc.
      ]);
      final dims = ImageBoundsProbe.probe(bytes);
      expect(dims, isNotNull);
      expect(dims!.width, 100);
      expect(dims.height, 200);
    });

    test('detects bombing PNG (50000 x 50000)', () {
      final bytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0xC3, 0x50, // width = 50000
        0x00, 0x00, 0xC3, 0x50, // height = 50000
        0x08, 0x02, 0x00, 0x00, 0x00,
      ]);
      final dims = ImageBoundsProbe.probe(bytes)!;
      expect(dims.exceeds(), isTrue);
    });

    test('returns null for unknown magic', () {
      final bytes = Uint8List(64); // all zeros
      expect(ImageBoundsProbe.probe(bytes), isNull);
    });

    test('exceeds() with custom thresholds', () {
      const dims = ImageDimensions(width: 1000, height: 1000);
      expect(dims.exceeds(maxSide: 500), isTrue);
      expect(dims.exceeds(maxPixels: 500 * 500), isTrue);
      expect(dims.exceeds(), isFalse);
    });
  });
}
