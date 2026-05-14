import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors.dart';
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

// (audit H6) Les anciennes `AttachmentTooLargeError`/`AttachmentRejectedError`
// définies localement sont déplacées dans `lib/core/errors.dart` et héritent
// désormais de `HealthError`, de sorte que `localiseError` les transforme en
// message stable plutôt que de tomber sur `errorGeneric`.

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

    // (audit sécu B1, DB v5) Filename chiffré au champ : empêche un
    // attaquant qui aurait cassé SQLCipher mais pas la VEK de lire le
    // nom (souvent identifiant : "facture-mme-durand.pdf"). La colonne
    // legacy `filename` reste vide pour les nouvelles rows.
    final filenameEnc = await _crypto.encryptString(workingFilename);

    final epoch = nowEpochSeconds();
    await _db
        .into(_db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: Value(id),
            ownerType: ownerType,
            ownerId: ownerId,
            kind: kind,
            // Plus jamais en clair : la colonne legacy reçoit "" pour les
            // nouvelles rows. C'est `filenameEncrypted` qui porte la donnée.
            filename: const Value(''),
            filenameEncrypted: Value(filenameEnc),
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
    Set<String> excludeKinds = const {AttachmentKind.avatar},
  }) {
    // `excludeKinds` par défaut = `{avatar}` : la liste générique des
    // pièces jointes (`AttachmentsSection`) n'a pas vocation à montrer
    // l'avatar — il a son propre widget (`AvatarPicker`) au sommet du
    // formulaire / de la fiche. Les anciens consumers continuent de
    // fonctionner sans changement (l'avatar est simplement filtré).
    // Pour récupérer absolument tout (export RGPD, panic-wipe), passer
    // `excludeKinds: const {}`.
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
    if (excludeKinds.isNotEmpty) {
      select.where((t) => t.kind.isNotIn(excludeKinds));
    }
    return select.watch().asyncMap((rows) async {
      final out = <Attachment>[];
      for (final r in rows) {
        out.add(await _fromRow(r));
      }
      return out;
    });
  }

  /// Définit (ou remplace) la photo-avatar du couple `(ownerType, ownerId)`.
  ///
  /// Invariant maintenu : **au plus un avatar `deletedAt IS NULL` par owner**.
  /// L'éventuel avatar courant est purgé (row + fichier `.enc`) avant
  /// l'import du nouveau, dans cet ordre — mieux vaut une fenêtre transitoire
  /// "pas d'avatar" que deux avatars concurrents pour le même owner.
  ///
  /// Le pipeline reste celui de [importBytes] : `ImageBoundsProbe` rejette
  /// les image-bombes avant decode, `ImageCompress.maybeCompress` downscale
  /// les photos 12 MP en isolate, AES-GCM via `FieldCrypto` puis
  /// écriture atomique sur disque + filename chiffré au champ. Aucune
  /// nouvelle surface crypto n'est introduite.
  ///
  /// Le `mimeType` doit commencer par `image/` ; sinon l'import échoue
  /// avec [AttachmentRejectedError]`('image_format_unrecognised')` côté
  /// [importBytes] (les bytes sans magic image connu sont refusés).
  Future<Attachment> setAvatar({
    required String ownerType,
    required String ownerId,
    required Uint8List bytes,
    required String mimeType,
    required String filename,
  }) async {
    // Refus précoce : un avatar DOIT être annoncé comme image. Sans ce garde,
    // un appelant qui passerait par erreur un mime `application/pdf` se
    // verrait stocker l'avatar côté DB sans déclencher `ImageBoundsProbe`
    // (qui n'agit que si `mimeType.startsWith('image/')` dans
    // [importBytes]). On protège donc l'invariant "avatar ⇒ image" ici,
    // et on laisse `importBytes` faire le check magic-bytes ensuite.
    if (!mimeType.startsWith('image/')) {
      throw const AttachmentRejectedError('image_format_unrecognised');
    }
    final current = await getAvatar(ownerType: ownerType, ownerId: ownerId);
    if (current != null) {
      await purge(current.id);
    }
    return importBytes(
      ownerType: ownerType,
      ownerId: ownerId,
      kind: AttachmentKind.avatar,
      filename: filename,
      mimeType: mimeType,
      bytes: bytes,
    );
  }

  /// Renvoie l'avatar courant du couple `(ownerType, ownerId)` ou `null`
  /// s'il n'y en a pas. Décrypte le filename (`_fromRow`) ; ne lit PAS le
  /// fichier `.enc` — voir [readBytes] pour ça.
  Future<Attachment?> getAvatar({
    required String ownerType,
    required String ownerId,
  }) async {
    final row =
        await (_db.select(_db.attachments)
              ..where(
                (t) =>
                    t.ownerType.equals(ownerType) &
                    t.ownerId.equals(ownerId) &
                    t.kind.equals(AttachmentKind.avatar) &
                    t.deletedAt.isNull(),
              )
              // Si plusieurs avatars existent (ne devrait jamais arriver,
              // `setAvatar` purge l'ancien), on prend le plus récent.
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return _fromRow(row);
  }

  /// Stream live de l'avatar du couple — émet `null` quand il n'y en a
  /// pas / vient d'être supprimé, l'`Attachment` mis à jour sinon. Utilisé
  /// par `OwnerAvatar` (UI tile) et `AvatarPicker` (formulaire / fiche)
  /// pour reconstruire dès que l'utilisateur change la photo, sans avoir
  /// à invalider manuellement le provider.
  Stream<Attachment?> watchAvatar({
    required String ownerType,
    required String ownerId,
  }) {
    final select = _db.select(_db.attachments)
      ..where(
        (t) =>
            t.ownerType.equals(ownerType) &
            t.ownerId.equals(ownerId) &
            t.kind.equals(AttachmentKind.avatar) &
            t.deletedAt.isNull(),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(1);
    return select.watch().asyncMap((rows) async {
      if (rows.isEmpty) return null;
      return _fromRow(rows.first);
    });
  }

  /// Supprime l'avatar courant si présent (purge row + fichier `.enc`).
  /// No-op s'il n'y a pas d'avatar — utile pour le bouton « Supprimer la
  /// photo » du `AvatarPicker`.
  Future<void> clearAvatar({
    required String ownerType,
    required String ownerId,
  }) async {
    final current = await getAvatar(ownerType: ownerType, ownerId: ownerId);
    if (current != null) {
      await purge(current.id);
    }
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

  /// (DB v5) Décrypte le filename si disponible (`filenameEncrypted`),
  /// retombe sinon sur la colonne legacy `filename` clair (rows v4-).
  /// Migration paresseuse : si on lit une row legacy, on la re-saisit
  /// avec sa version chiffrée + on vide `filename`. Idempotente.
  Future<Attachment> _fromRow(AttachmentRow r) async {
    String name;
    final enc = r.filenameEncrypted;
    if (enc != null && enc.isNotEmpty) {
      name = await _crypto.decryptString(enc);
    } else if (r.filename.isNotEmpty) {
      name = r.filename;
      // Migration paresseuse (audit sécu B1) — best-effort.
      try {
        final ciphertext = await _crypto.encryptString(name);
        await (_db.update(
          _db.attachments,
        )..where((t) => t.id.equals(r.id))).write(
          AttachmentsCompanion(
            filename: const Value(''),
            filenameEncrypted: Value(ciphertext),
          ),
        );
      } on Object {
        // ignore : on retentera à la prochaine lecture.
      }
    } else {
      name = '';
    }
    return Attachment(
      id: r.id,
      ownerType: r.ownerType,
      ownerId: r.ownerId,
      kind: r.kind,
      filename: name,
      mimeType: r.mimeType,
      sizeBytes: r.sizeBytes,
      storagePath: r.storagePath,
      createdAt: secondsToDate(r.createdAt),
    );
  }
}
