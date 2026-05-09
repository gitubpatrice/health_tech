import 'dart:typed_data';

/// Lightweight image dimension probe — reads only the magic bytes / first
/// chunks rather than decoding the full image. Used to reject "image bomb"
/// files before they reach the decoder (which would allocate width × height
/// × 4 bytes and OOM).
///
/// Supports: PNG (IHDR), JPEG (SOFn), WebP (VP8/VP8L/VP8X), GIF (header).
/// Returns `null` when the format is unrecognised — callers should treat
/// `null` as "do not decode".
class ImageDimensions {
  const ImageDimensions({required this.width, required this.height});
  final int width;
  final int height;

  /// True if either side exceeds [maxSide] OR the total pixel count exceeds
  /// [maxPixels]. Defaults reject anything above 8000 × 8000 or 32 megapixels.
  bool exceeds({int maxSide = 8000, int maxPixels = 32 * 1000 * 1000}) {
    if (width <= 0 || height <= 0) return true;
    if (width > maxSide || height > maxSide) return true;
    if (width * height > maxPixels) return true;
    return false;
  }
}

class ImageBoundsProbe {
  const ImageBoundsProbe._();

  /// Returns dimensions if the magic bytes match a known format and dimensions
  /// can be extracted; null otherwise.
  static ImageDimensions? probe(Uint8List bytes) {
    if (bytes.length < 16) return null;
    return _probePng(bytes) ??
        _probeJpeg(bytes) ??
        _probeGif(bytes) ??
        _probeWebp(bytes);
  }

  // PNG: 89 50 4E 47 0D 0A 1A 0A then IHDR chunk at offset 8.
  static ImageDimensions? _probePng(Uint8List b) {
    if (b.length < 24) return null;
    const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (var i = 0; i < 8; i++) {
      if (b[i] != sig[i]) return null;
    }
    // IHDR chunk: 4 bytes length + 4 bytes 'IHDR' + width(4) + height(4)...
    final w = _readUint32BE(b, 16);
    final h = _readUint32BE(b, 20);
    return ImageDimensions(width: w, height: h);
  }

  // JPEG: starts with FF D8. Walk markers until SOFn (C0..CF except C4, C8, CC).
  static ImageDimensions? _probeJpeg(Uint8List b) {
    if (b[0] != 0xFF || b[1] != 0xD8) return null;
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) return null;
      final marker = b[i + 1];
      if (marker == 0xD8 || marker == 0xD9) return null;
      final segLen = (b[i + 2] << 8) | b[i + 3];
      final isSOF = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSOF) {
        // SOFn payload: precision(1) + height(2) + width(2) + ...
        final h = (b[i + 5] << 8) | b[i + 6];
        final w = (b[i + 7] << 8) | b[i + 8];
        return ImageDimensions(width: w, height: h);
      }
      i += 2 + segLen;
    }
    return null;
  }

  // GIF: 'GIF87a' or 'GIF89a' then logical screen width/height as little-endian.
  static ImageDimensions? _probeGif(Uint8List b) {
    if (b[0] != 0x47 || b[1] != 0x49 || b[2] != 0x46) return null;
    final w = b[6] | (b[7] << 8);
    final h = b[8] | (b[9] << 8);
    return ImageDimensions(width: w, height: h);
  }

  // WebP: RIFF....WEBP then VP8/VP8L/VP8X chunk.
  static ImageDimensions? _probeWebp(Uint8List b) {
    if (b.length < 30) return null;
    if (b[0] != 0x52 || b[1] != 0x49 || b[2] != 0x46 || b[3] != 0x46) {
      return null;
    }
    if (b[8] != 0x57 || b[9] != 0x45 || b[10] != 0x42 || b[11] != 0x50) {
      return null;
    }
    final chunk = String.fromCharCodes(b.sublist(12, 16));
    switch (chunk) {
      case 'VP8 ':
        // Lossy: dims at bytes 26-29 (little-endian, 14-bit each).
        final w = ((b[26] | (b[27] << 8)) & 0x3FFF) + 0;
        final h = ((b[28] | (b[29] << 8)) & 0x3FFF) + 0;
        return ImageDimensions(width: w, height: h);
      case 'VP8L':
        // Lossless: 1 signature byte then 14-bit width-1 / height-1.
        final v = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
        final w = (v & 0x3FFF) + 1;
        final h = ((v >> 14) & 0x3FFF) + 1;
        return ImageDimensions(width: w, height: h);
      case 'VP8X':
        // Extended: 24-bit width-1 / height-1 starting at byte 24.
        final w = (b[24] | (b[25] << 8) | (b[26] << 16)) + 1;
        final h = (b[27] | (b[28] << 8) | (b[29] << 16)) + 1;
        return ImageDimensions(width: w, height: h);
      default:
        return null;
    }
  }

  static int _readUint32BE(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
}
