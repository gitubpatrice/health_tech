import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Downscale + re-encode an image to keep attachment size under control.
///
/// Why:
///   A 12 MP photo from a modern phone is ~3–5 MB JPEG and decodes to
///   ~50 MB of RGBA in memory. Storing dozens of them per client makes
///   backups slow, decryption visible, and shares painful. The vast
///   majority of practitioner use-cases (skin condition, posture, site
///   photo) need ≤ 2048 px on the long side — far below sensor resolution.
///
/// Strategy:
///   1. Skip if the input is already small (≤ [_maxLongSide] px AND
///      ≤ [_skipUnderBytes] bytes) — no point re-encoding.
///   2. Otherwise decode, resize so the long side equals [_maxLongSide],
///      and re-encode JPEG at [_jpegQuality]. Keep the original if the
///      result somehow ends up larger (rare, e.g. cartoon PNG → JPEG).
///   3. Run on a background isolate so a 12 MP decode does not freeze
///      the UI thread on a mid-range phone.
///
/// Returns the (possibly compressed) bytes plus the MIME type that
/// matches them — JPEG when we re-encoded, the original MIME otherwise.
class ImageCompress {
  const ImageCompress._();

  /// Default cap at 2048 px on the long side (matches what most practitioner
  /// detail photos actually need; can be tuned per call).
  static const int _maxLongSide = 2048;

  /// JPEG quality when re-encoding. 85 is the canonical "visually
  /// indistinguishable" sweet spot; larger files for marginal quality.
  static const int _jpegQuality = 85;

  /// Below this threshold we skip re-encoding even if dimensions exceed
  /// the cap — a 200 KB photo is not worth the CPU cost.
  static const int _skipUnderBytes = 300 * 1024;

  /// Compress when needed. The returned [CompressedImage.mimeType] reflects
  /// what the bytes actually are after the call: it stays equal to [mime]
  /// when no work was done, and switches to `image/jpeg` when re-encoded.
  static Future<CompressedImage> maybeCompress({
    required Uint8List bytes,
    required String mime,
    int maxLongSide = _maxLongSide,
    int jpegQuality = _jpegQuality,
  }) async {
    // GIFs and other animated formats lose their animation if we re-encode
    // through `image`, so leave them alone. Restrict the active path to the
    // formats Health Tech is likely to receive from a phone camera.
    if (mime != 'image/jpeg' && mime != 'image/png' && mime != 'image/webp') {
      return CompressedImage(bytes: bytes, mimeType: mime);
    }
    if (bytes.length <= _skipUnderBytes) {
      return CompressedImage(bytes: bytes, mimeType: mime);
    }

    final compressed = await compute<_CompressInput, Uint8List?>(
      _compressInIsolate,
      _CompressInput(
        bytes: bytes,
        maxLongSide: maxLongSide,
        jpegQuality: jpegQuality,
      ),
    );
    if (compressed == null || compressed.length >= bytes.length) {
      return CompressedImage(bytes: bytes, mimeType: mime);
    }
    return CompressedImage(bytes: compressed, mimeType: 'image/jpeg');
  }
}

class CompressedImage {
  const CompressedImage({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;
}

class _CompressInput {
  const _CompressInput({
    required this.bytes,
    required this.maxLongSide,
    required this.jpegQuality,
  });
  final Uint8List bytes;
  final int maxLongSide;
  final int jpegQuality;
}

/// Worker entry point — runs in the isolate spawned by [compute]. Returns
/// `null` on any decode failure so the caller can fall back to the
/// uncompressed bytes.
Uint8List? _compressInIsolate(_CompressInput input) {
  try {
    final decoded = img.decodeImage(input.bytes);
    if (decoded == null) return null;
    final longSide = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    final src = longSide > input.maxLongSide
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? input.maxLongSide : null,
            height: decoded.height > decoded.width ? input.maxLongSide : null,
            interpolation: img.Interpolation.cubic,
          )
        : decoded;
    return Uint8List.fromList(img.encodeJpg(src, quality: input.jpegQuality));
  } on Object {
    return null;
  }
}
