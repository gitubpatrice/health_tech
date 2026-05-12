import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors.dart';
import '../../domain/session.dart';
import '../../utils/clock.dart';
import '../db/database.dart';
import '../vault/field_crypto.dart';
import '_helpers.dart';

class SessionRepository {
  SessionRepository(this._db, this._crypto);

  final HealthDb _db;
  final FieldCrypto _crypto;
  final Uuid _uuid = const Uuid();

  Future<Session> create(Session draft) async {
    if (!draft.endAt.isAfter(draft.startAt)) {
      throw const ValidationError('session_end_before_start', 'endAt');
    }
    final id = draft.id.isEmpty ? _uuid.v4() : draft.id;
    final now = nowEpochSeconds();
    final companion = await _toCompanion(
      draft.copyWith(id: id),
      isInsert: true,
      epoch: now,
    );
    await _db.into(_db.sessions).insert(companion);
    return (await getById(id))!;
  }

  Future<Session> update(Session session) async {
    final now = nowEpochSeconds();
    final companion = await _toCompanion(session, isInsert: false, epoch: now);
    await (_db.update(
      _db.sessions,
    )..where((t) => t.id.equals(session.id))).write(companion);
    return (await getById(session.id))!;
  }

  Future<void> clearCalendarIds(String id) async {
    await (_db.update(_db.sessions)..where((t) => t.id.equals(id))).write(
      const SessionsCompanion(
        externalCalendarId: Value(null),
        externalCalendarEventId: Value(null),
      ),
    );
  }

  Future<Session?> getById(String id) async {
    final row = await (_db.select(
      _db.sessions,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (row == null) return null;
    return _fromRow(row);
  }

  Stream<List<Session>> watchByClient(String clientId) {
    final select = _db.select(_db.sessions)
      ..where((t) => t.clientId.equals(clientId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.startAt)]);
    return select.watch().map(
      (rows) => rows.map(_fromRowLight).toList(growable: false),
    );
  }

  Stream<List<Session>> watchByAnimal(String animalId) {
    final select = _db.select(_db.sessions)
      ..where((t) => t.animalId.equals(animalId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.startAt)]);
    return select.watch().map(
      (rows) => rows.map(_fromRowLight).toList(growable: false),
    );
  }

  Stream<List<Session>> watchInRange(DateTime from, DateTime to) {
    final fromS = dateToSeconds(from);
    final toS = dateToSeconds(to);
    final select = _db.select(_db.sessions)
      ..where(
        (t) => t.deletedAt.isNull() & t.startAt.isBetweenValues(fromS, toS),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.startAt)]);
    return select.watch().map(
      (rows) => rows.map(_fromRowLight).toList(growable: false),
    );
  }

  Future<void> softDelete(String id) async {
    final now = nowEpochSeconds();
    await (_db.update(_db.sessions)..where((t) => t.id.equals(id))).write(
      SessionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  Future<void> purge(String id) async {
    await (_db.delete(_db.sessions)..where((t) => t.id.equals(id))).go();
  }

  // -- mapping ---------------------------------------------------------------

  Future<SessionsCompanion> _toCompanion(
    Session s, {
    required bool isInsert,
    required int epoch,
  }) async {
    final reportEncrypted = s.report.isEmpty
        ? const Value<String?>(null)
        : Value(await _crypto.encryptString(jsonEncode(s.report.toJson())));
    final privateEncrypted = await encryptOptional(_crypto, s.privateNote);
    return SessionsCompanion(
      id: Value(s.id),
      clientId: Value(s.clientId),
      animalId: Value(s.animalId),
      startAt: Value(dateToSeconds(s.startAt)),
      endAt: Value(dateToSeconds(s.endAt)),
      kind: Value(s.kind),
      location: Value(s.location),
      status: Value(s.status),
      motivesJson: Value(s.motives),
      priceCents: Value(s.priceCents),
      paymentStatus: Value(s.paymentStatus),
      paymentMethod: Value(s.paymentMethod),
      reportEncrypted: reportEncrypted,
      privateNoteEncrypted: privateEncrypted,
      improvementLevel: Value(s.improvementLevel),
      nextSuggestedAt: Value(
        s.nextSuggestedAt == null ? null : dateToSeconds(s.nextSuggestedAt!),
      ),
      externalCalendarId: Value(s.externalCalendarId),
      externalCalendarEventId: Value(s.externalCalendarEventId),
      updatedAt: Value(epoch),
      createdAt: isInsert ? Value(epoch) : const Value.absent(),
    );
  }

  Future<Session> _fromRow(SessionRow row) async {
    final report = row.reportEncrypted == null
        ? const SessionReport()
        : SessionReport.fromJson(
            jsonDecode(await _crypto.decryptString(row.reportEncrypted!))
                as Map<String, dynamic>,
          );
    final privateNote = row.privateNoteEncrypted == null
        ? ''
        : await _crypto.decryptString(row.privateNoteEncrypted!);
    return _baseFromRow(row).copyWith(report: report, privateNote: privateNote);
  }

  Session _fromRowLight(SessionRow row) => _baseFromRow(row);

  Session _baseFromRow(SessionRow row) => Session(
    id: row.id,
    clientId: row.clientId,
    animalId: row.animalId,
    startAt: secondsToDate(row.startAt),
    endAt: secondsToDate(row.endAt),
    kind: row.kind,
    location: row.location,
    status: row.status,
    motives: row.motivesJson,
    priceCents: row.priceCents,
    paymentStatus: row.paymentStatus,
    paymentMethod: row.paymentMethod,
    improvementLevel: row.improvementLevel,
    nextSuggestedAt: row.nextSuggestedAt == null
        ? null
        : secondsToDate(row.nextSuggestedAt!),
    externalCalendarId: row.externalCalendarId,
    externalCalendarEventId: row.externalCalendarEventId,
    createdAt: secondsToDate(row.createdAt),
    updatedAt: secondsToDate(row.updatedAt),
  );
}
