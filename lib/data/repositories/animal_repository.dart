import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/animal.dart';
import '../../utils/clock.dart';
import '../db/database.dart';
import '../vault/field_crypto.dart';
import '_helpers.dart';

class AnimalRepository {
  AnimalRepository(this._db, this._crypto);

  final HealthDb _db;
  final FieldCrypto _crypto;
  final Uuid _uuid = const Uuid();

  Future<Animal> create(Animal draft) async {
    final id = draft.id.isEmpty ? _uuid.v4() : draft.id;
    final now = nowEpochSeconds();
    final companion = await _toCompanion(
      draft.copyWith(id: id),
      isInsert: true,
      epoch: now,
    );
    await _db.into(_db.animals).insert(companion);
    return (await getById(id))!;
  }

  Future<Animal> update(Animal animal) async {
    final now = nowEpochSeconds();
    final companion = await _toCompanion(animal, isInsert: false, epoch: now);
    await (_db.update(
      _db.animals,
    )..where((t) => t.id.equals(animal.id))).write(companion);
    return (await getById(animal.id))!;
  }

  Future<Animal?> getById(String id) async {
    final row = await (_db.select(
      _db.animals,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (row == null) return null;
    return _fromRow(row);
  }

  Stream<List<Animal>> watchByClient(String clientId) {
    final select = _db.select(_db.animals)
      ..where((t) => t.clientId.equals(clientId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return select.watch().map(
      (rows) => rows.map(_fromRowLight).toList(growable: false),
    );
  }

  Stream<List<Animal>> watchAll({String? query, String? speciesFilter}) {
    final select = _db.select(_db.animals)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    if (query != null && query.trim().isNotEmpty) {
      final pattern = '%${query.trim()}%';
      select.where((t) => t.name.like(pattern) | t.breed.like(pattern));
    }
    if (speciesFilter != null && speciesFilter.isNotEmpty) {
      select.where((t) => t.species.equals(speciesFilter));
    }
    return select.watch().map(
      (rows) => rows.map(_fromRowLight).toList(growable: false),
    );
  }

  Future<void> softDelete(String id) async {
    final now = nowEpochSeconds();
    await (_db.update(_db.animals)..where((t) => t.id.equals(id))).write(
      AnimalsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  Future<void> purge(String id) async {
    await (_db.delete(_db.animals)..where((t) => t.id.equals(id))).go();
  }

  // -- mapping ---------------------------------------------------------------

  Future<AnimalsCompanion> _toCompanion(
    Animal a, {
    required bool isInsert,
    required int epoch,
  }) async {
    final health = await encryptOptional(_crypto, a.healthNotes);
    final behavior = await encryptOptional(_crypto, a.behaviorNotes);
    return AnimalsCompanion(
      id: Value(a.id),
      clientId: Value(a.clientId),
      name: Value(a.name),
      species: Value(a.species),
      breed: Value(a.breed),
      sex: Value(a.sex),
      birthDateMs: Value(a.birthDate?.millisecondsSinceEpoch),
      weightGrams: Value(a.weightGrams),
      color: Value(a.color),
      identifiersJson: Value(a.identifiers.toJson()),
      profileJson: Value(a.profile),
      healthNotesEncrypted: health,
      behaviorNotesEncrypted: behavior,
      updatedAt: Value(epoch),
      createdAt: isInsert ? Value(epoch) : const Value.absent(),
    );
  }

  Future<Animal> _fromRow(AnimalRow row) async {
    final health = row.healthNotesEncrypted == null
        ? ''
        : await _crypto.decryptString(row.healthNotesEncrypted!);
    final behavior = row.behaviorNotesEncrypted == null
        ? ''
        : await _crypto.decryptString(row.behaviorNotesEncrypted!);
    return _baseFromRow(
      row,
    ).copyWith(healthNotes: health, behaviorNotes: behavior);
  }

  Animal _fromRowLight(AnimalRow row) => _baseFromRow(row);

  Animal _baseFromRow(AnimalRow row) => Animal(
    id: row.id,
    clientId: row.clientId,
    name: row.name,
    species: row.species,
    breed: row.breed,
    sex: row.sex,
    birthDate: row.birthDateMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.birthDateMs!),
    weightGrams: row.weightGrams,
    color: row.color,
    identifiers: row.identifiersJson.isEmpty
        ? const AnimalIdentifiers()
        : AnimalIdentifiers.fromJson(row.identifiersJson),
    profile: row.profileJson,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt * 1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt * 1000),
  );
}
