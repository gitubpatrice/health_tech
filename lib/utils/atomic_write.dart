import 'dart:io';
import 'dart:typed_data';

/// Writes [bytes] atomically: creates a temp file in the same directory,
/// flushes + closes it, then renames over the destination. This guarantees
/// that observers either see the old file or the fully-written new one,
/// never a half-written one. Critical for vault payloads.
Future<File> atomicWriteBytes(File destination, Uint8List bytes) async {
  await destination.parent.create(recursive: true);
  final tmp = File(
    '${destination.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
  );
  RandomAccessFile? raf;
  try {
    raf = await tmp.open(mode: FileMode.writeOnly);
    await raf.writeFrom(bytes);
    await raf.flush();
    await raf.close();
    raf = null;
    return await tmp.rename(destination.path);
  } finally {
    if (raf != null) {
      await raf.close().catchError((_) => raf!);
    }
    if (tmp.existsSync()) {
      try {
        await tmp.delete();
      } on FileSystemException {
        // best-effort cleanup of stale temp
      }
    }
  }
}
