import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/tag.dart';
import '../db/database.dart';

class TagRepository {
  TagRepository(this._db);

  final HealthDb _db;
  final Uuid _uuid = const Uuid();

  Future<Tag> upsert({String? id, required String label, int? colorArgb}) async {
    final normalised = label.trim();
    if (normalised.isEmpty) {
      throw ArgumentError.value(label, 'label', 'Tag label must not be empty');
    }
    if (id == null) {
      // Reuse an existing tag with the same label (case-insensitive) instead
      // of creating a duplicate — tags are user-facing labels.
      final existing = await (_db.select(_db.tags)
            ..where((t) => t.label.lower().equals(normalised.toLowerCase())))
          .getSingleOrNull();
      if (existing != null) {
        return Tag(
          id: existing.id,
          label: existing.label,
          colorArgb: existing.colorArgb,
        );
      }
    }
    final tagId = id ?? _uuid.v4();
    await _db.into(_db.tags).insertOnConflictUpdate(
          TagsCompanion.insert(
            id: Value(tagId),
            label: normalised,
            colorArgb: Value(colorArgb),
          ),
        );
    return Tag(id: tagId, label: normalised, colorArgb: colorArgb);
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();
  }

  Stream<List<Tag>> watchAll() {
    return (_db.select(_db.tags)
          ..orderBy([(t) => OrderingTerm.asc(t.label)]))
        .watch()
        .map((rows) => rows
            .map((r) =>
                Tag(id: r.id, label: r.label, colorArgb: r.colorArgb))
            .toList(growable: false));
  }

  Future<void> link({
    required String tagId,
    required String ownerType,
    required String ownerId,
  }) async {
    await _db.into(_db.tagLinks).insertOnConflictUpdate(
          TagLinksCompanion.insert(
            tagId: tagId,
            ownerType: ownerType,
            ownerId: ownerId,
          ),
        );
  }

  Future<void> unlink({
    required String tagId,
    required String ownerType,
    required String ownerId,
  }) async {
    await (_db.delete(_db.tagLinks)
          ..where((t) =>
              t.tagId.equals(tagId) &
              t.ownerType.equals(ownerType) &
              t.ownerId.equals(ownerId)))
        .go();
  }

  Stream<List<Tag>> watchForOwner({
    required String ownerType,
    required String ownerId,
  }) {
    final query = _db.select(_db.tags).join([
      innerJoin(
        _db.tagLinks,
        _db.tagLinks.tagId.equalsExp(_db.tags.id),
      ),
    ])
      ..where(_db.tagLinks.ownerType.equals(ownerType) &
          _db.tagLinks.ownerId.equals(ownerId))
      ..orderBy([OrderingTerm.asc(_db.tags.label)]);
    return query.watch().map((rows) => rows
        .map((r) => r.readTable(_db.tags))
        .map((r) => Tag(id: r.id, label: r.label, colorArgb: r.colorArgb))
        .toList(growable: false));
  }

  /// Returns the IDs of owners (of the given type) that have ALL [tagIds]
  /// attached. Empty `tagIds` returns null (caller skips filtering).
  Future<Set<String>?> ownerIdsTaggedWithAll({
    required String ownerType,
    required List<String> tagIds,
  }) async {
    if (tagIds.isEmpty) return null;
    final query = _db.selectOnly(_db.tagLinks)
      ..addColumns([_db.tagLinks.ownerId])
      ..where(_db.tagLinks.ownerType.equals(ownerType) &
          _db.tagLinks.tagId.isIn(tagIds))
      ..groupBy(
        [_db.tagLinks.ownerId],
        having: _db.tagLinks.tagId.count(distinct: true).equals(tagIds.length),
      );
    final rows = await query.get();
    return rows
        .map((r) => r.read(_db.tagLinks.ownerId)!)
        .toSet();
  }
}
