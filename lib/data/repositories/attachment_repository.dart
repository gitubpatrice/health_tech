import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/attachment.dart';
import '../../utils/atomic_write.dart';
import '../../utils/clock.dart';
import '../../utils/image_bounds.dart';
import '../../utils/image_compress.dart';
import '../db/database.dart';
import '../vault/field_crypto.dart';
import '_helpers.dart';

/// Maximum attachment size accepted by the import flow. Above this we refuse
/// to load the file in memory at all (the picker still streams to a path,
/// but we read in one shot for encryption). Adjust if needed.
const int kMaxAttachmentBytes = 25 * 1024 * 1024; // 25 MiB

class AttachmentTooLargeError implements Exception {
  const AttachmentTooLargeError(this.size);
  final int size;
  @override
  String toString() => 'Attachment too large ($size bytes)';
}

class AttachmentRejectedError implements Exception {
  const AttachmentRejectedError(this.reason);
  final String reason;
  @override
  String toString() => 'Attachment rejected: $reason';
}

class AttachmentRepository {
  AttachmentRepository(this._db, this._crypto);

  final HealthDb _db;
  final FieldCrypto _crypto;
  final Uuid _uuid = const Uuid();

  static const String _attachmentsDir = 'attachments';

  Future<Directory> _baseDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, _attachmentsDir));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _fileFor(String storagePath) async {
    final dir = await _baseDir();
    return File(p.join(dir.path, storagePath));
  }

  /// Imports a file from its bytes — encrypts and persists in
  /// `<appSupport>/attachments/<uuid>.enc`, with metadata in DB.
  ///
  /// For images, runs an [ImageBoundsProbe] first and rejects bombs before
  /// the bytes ever reach a decoder. For non-images, only the size cap
  /// applies (the file is opaque to us anyway).
  Future<Attachment> importBytes({
    required String ownerType,
    required String ownerId,
    required String kind,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (bytes.length > kMaxAttachmentBytes) {
      throw AttachmentTooLargeError(bytes.length);
    }
    var workingBytes = bytes;
    var workingMime = mimeType;
    var workingFilename = filename;
    if (mimeType.startsWith('image/')) {
      final dims = ImageBoundsProbe.probe(bytes);
      if (dims == null) {
        throw const AttachmentRejectedError('image_format_unrecognised');
      }
      if (dims.exceeds()) {
        throw const AttachmentRejectedError('image_too_large');
      }
      // Downscale + re-encode huge phone photos so we don't ship 5 MB
      // JPEGs into the encrypted store. Runs in an isolate so a 12 MP
      // decode does not freeze the UI. If the compressor returns the
      // bytes unchanged (small image, decode failure, or larger output),
      // we keep the original.
      final compressed = await ImageCompress.maybeCompress(
        bytes: bytes,
        mime: mimeType,
      );
      workingBytes = compressed.bytes;
      if (compressed.mimeType != mimeType) {
        workingMime = compressed.mimeType;
        workingFilename = _swapExtension(filename, '.jpg');
      }
    }

    final id = _uuid.v4();
    final storagePath = '$id.enc';
    final encrypted = await _crypto.encryptBytes(workingBytes);
    final file = await _fileFor(storagePath);
    await atomicWriteBytes(file, encrypted);

    final epoch = nowEpochSeconds();
    await _db
        .into(_db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: Value(id),
            ownerType: ownerType,
            ownerId: ownerId,
            kind: kind,
            filename: workingFilename,
            mimeType: workingMime,
            sizeBytes: workingBytes.length,
            storagePath: storagePath,
            nonceB64: '',
            createdAt: Value(epoch),
            updatedAt: Value(epoch),
          ),
        );
    return Attachment(
      id: id,
      ownerType: ownerType,
      ownerId: ownerId,
      kind: kind,
      filename: workingFilename,
      mimeType: workingMime,
      sizeBytes: workingBytes.length,
      storagePath: storagePath,
      createdAt: secondsToDate(epoch),
    );
  }

  /// Replace (or append) the file extension. Used after image compression
  /// re-encodes a PNG/WebP as JPEG so the stored filename stays consistent
  /// with the actual bytes — `paw.png` becomes `paw.jpg`.
  static String _swapExtension(String filename, String newExt) {
    final dot = filename.lastIndexOf('.');
    final stem = dot <= 0 ? filename : filename.substring(0, dot);
    return '$stem$newExt';
  }

  Future<Uint8List> readBytes(String id) async {
    final row = await (_db.select(
      _db.attachments,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) throw StateError('Attachment $id not found');
    final file = await _fileFor(row.storagePath);
    final encrypted = await file.readAsBytes();
    return _crypto.decryptBytes(encrypted);
  }

  Stream<List<Attachment>> watchByOwner({
    required String ownerType,
    required String ownerId,
    String? kindFilter,
  }) {
    final select = _db.select(_db.attachments)
      ..where(
        (t) =>
            t.ownerType.equals(ownerType) &
            t.ownerId.equals(ownerId) &
            t.deletedAt.isNull(),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (kindFilter != null) {
      select.where((t) => t.kind.equals(kindFilter));
    }
    return select.watch().map(
      (rows) => rows.map(_fromRow).toList(growable: false),
    );
  }

  /// Removes the row AND the encrypted file. Best-effort: row deletion is
  /// authoritative, file delete failures are logged but don't fail the call
  /// (the file becomes orphan, cleaned by [purgeOrphans]).
  Future<void> purge(String id) async {
    final row = await (_db.select(
      _db.attachments,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (_db.delete(_db.attachments)..where((t) => t.id.equals(id))).go();
    final file = await _fileFor(row.storagePath);
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // ignore: orphan file will be reclaimed by purgeOrphans()
    }
  }

  /// Cascading delete used when an owner (client/animal/session) is purged.
  Future<int> purgeAllForOwner({
    required String ownerType,
    required String ownerId,
  }) async {
    final rows =
        await (_db.select(_db.attachments)..where(
              (t) => t.ownerType.equals(ownerType) & t.ownerId.equals(ownerId),
            ))
            .get();
    for (final r in rows) {
      final file = await _fileFor(r.storagePath);
      try {
        if (file.existsSync()) await file.delete();
      } on FileSystemException {
        // ignore: orphan
      }
    }
    return (_db.delete(_db.attachments)..where(
          (t) => t.ownerType.equals(ownerType) & t.ownerId.equals(ownerId),
        ))
        .go();
  }

  /// Sweeps the attachments directory and removes files that have no row in
  /// the database. Should be invoked at app boot.
  Future<int> purgeOrphans() async {
    final dir = await _baseDir();
    if (!dir.existsSync()) return 0;
    final knownPaths = (await _db.select(_db.attachments).get())
        .map((r) => r.storagePath)
        .toSet();
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!knownPaths.contains(name)) {
        try {
          await entity.delete();
          removed++;
        } on FileSystemException {
          // ignore
        }
      }
    }
    return removed;
  }

  Attachment _fromRow(AttachmentRow r) => Attachment(
    id: r.id,
    ownerType: r.ownerType,
    ownerId: r.ownerId,
    kind: r.kind,
    filename: r.filename,
    mimeType: r.mimeType,
    sizeBytes: r.sizeBytes,
    storagePath: r.storagePath,
    createdAt: secondsToDate(r.createdAt),
  );
}
