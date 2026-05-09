import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();
final _rng = Random.secure();

/// Writes [bytes] atomically: creates a temp file in the same directory,
/// flushes + closes it, then renames over the destination. This guarantees
/// that observers either see the old file or the fully-written new one,
/// never a half-written one. Critical for vault payloads.
///
/// The temp file uses a UUID v4 suffix (not a microsecond timestamp) so
/// concurrent writes against the same destination cannot collide on a
/// device with a low-resolution monotonic clock.
Future<File> atomicWriteBytes(File destination, Uint8List bytes) async {
  await destination.parent.create(recursive: true);
  // Mix a UUID v4 + 32 random bits — UUID guards against time correlation,
  // the extra entropy guards against an unlikely UUID collision in the same
  // process tree.
  final tmpSuffix = '${_uuid.v4()}-${_rng.nextInt(1 << 32)}';
  final tmp = File('${destination.path}.tmp-$tmpSuffix');
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
