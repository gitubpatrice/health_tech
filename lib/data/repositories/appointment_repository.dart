import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors.dart';
import '../../domain/appointment.dart';
import '../../utils/clock.dart';
import '../db/database.dart';
import '../vault/field_crypto.dart';
import '_helpers.dart';

class AppointmentRepository {
  AppointmentRepository(this._db, this._crypto);

  final HealthDb _db;
  final FieldCrypto _crypto;
  final Uuid _uuid = const Uuid();

  Future<Appointment> create(Appointment draft) async {
    if (!draft.endAt.isAfter(draft.startAt)) {
      throw const ValidationError('appointment_end_before_start', 'endAt');
    }
    final id = draft.id.isEmpty ? _uuid.v4() : draft.id;
    final epoch = nowEpochSeconds();
    final companion =
        await _toCompanion(draft.copyWith(id: id), isInsert: true, epoch: epoch);
    await _db.into(_db.appointments).insert(companion);
    return (await getById(id))!;
  }

  Future<Appointment> update(Appointment a) async {
    final epoch = nowEpochSeconds();
    final companion = await _toCompanion(a, isInsert: false, epoch: epoch);
    await (_db.update(_db.appointments)..where((t) => t.id.equals(a.id)))
        .write(companion);
    return (await getById(a.id))!;
  }

  Future<Appointment?> getById(String id) async {
    final row = await (_db.select(_db.appointments)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    return _fromRow(row);
  }

  Stream<List<Appointment>> watchInRange(DateTime from, DateTime to) {
    final fromS = from.millisecondsSinceEpoch ~/ 1000;
    final toS = to.millisecondsSinceEpoch ~/ 1000;
    final select = _db.select(_db.appointments)
      ..where((t) =>
          t.deletedAt.isNull() &
          t.startAt.isBetweenValues(fromS, toS))
      ..orderBy([(t) => OrderingTerm.asc(t.startAt)]);
    return select.watch().map(
          (rows) => rows.map(_fromRowLight).toList(growable: false),
        );
  }

  Stream<List<Appointment>> watchByClient(String clientId) {
    final select = _db.select(_db.appointments)
      ..where((t) => t.deletedAt.isNull() & t.clientId.equals(clientId))
      ..orderBy([(t) => OrderingTerm.desc(t.startAt)]);
    return select.watch().map(
          (rows) => rows.map(_fromRowLight).toList(growable: false),
        );
  }

  Stream<List<Appointment>> watchUpcoming({int limit = 50}) {
    final nowS = nowEpochSeconds();
    final select = _db.select(_db.appointments)
      ..where((t) =>
          t.deletedAt.isNull() & t.startAt.isBiggerOrEqualValue(nowS))
      ..orderBy([(t) => OrderingTerm.asc(t.startAt)])
      ..limit(limit);
    return select.watch().map(
          (rows) => rows.map(_fromRowLight).toList(growable: false),
        );
  }

  Future<void> softDelete(String id) async {
    final epoch = nowEpochSeconds();
    await (_db.update(_db.appointments)..where((t) => t.id.equals(id))).write(
      AppointmentsCompanion(
        deletedAt: Value(epoch),
        updatedAt: Value(epoch),
      ),
    );
  }

  Future<void> purge(String id) async {
    await (_db.delete(_db.appointments)..where((t) => t.id.equals(id))).go();
  }

  // -- mapping ---------------------------------------------------------------

  Future<AppointmentsCompanion> _toCompanion(
    Appointment a, {
    required bool isInsert,
    required int epoch,
  }) async {
    final notes = await encryptOptional(_crypto, a.notes);
    return AppointmentsCompanion(
      id: Value(a.id),
      clientId: Value(a.clientId),
      animalId: Value(a.animalId),
      sessionId: Value(a.sessionId),
      startAt: Value(a.startAt.millisecondsSinceEpoch ~/ 1000),
      endAt: Value(a.endAt.millisecondsSinceEpoch ~/ 1000),
      title: Value(a.title),
      location: Value(a.location),
      kind: Value(a.kind),
      status: Value(a.status),
      reminderMinutesBefore: Value(a.reminderMinutesBefore),
      externalCalendarEventId: Value(a.externalCalendarEventId),
      externalCalendarId: Value(a.externalCalendarId),
      notesEncrypted: notes,
      updatedAt: Value(epoch),
      createdAt: isInsert ? Value(epoch) : const Value.absent(),
    );
  }

  Future<Appointment> _fromRow(AppointmentRow r) async {
    final notes = r.notesEncrypted == null
        ? ''
        : await _crypto.decryptString(r.notesEncrypted!);
    return _baseFromRow(r).copyWith(notes: notes);
  }

  Appointment _fromRowLight(AppointmentRow r) => _baseFromRow(r);

  Appointment _baseFromRow(AppointmentRow r) => Appointment(
        id: r.id,
        clientId: r.clientId,
        animalId: r.animalId,
        sessionId: r.sessionId,
        startAt: DateTime.fromMillisecondsSinceEpoch(r.startAt * 1000),
        endAt: DateTime.fromMillisecondsSinceEpoch(r.endAt * 1000),
        title: r.title,
        location: r.location,
        kind: r.kind,
        status: r.status,
        reminderMinutesBefore: r.reminderMinutesBefore,
        externalCalendarEventId: r.externalCalendarEventId,
        externalCalendarId: r.externalCalendarId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt * 1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAt * 1000),
      );
}
