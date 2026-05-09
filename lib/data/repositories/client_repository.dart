import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors.dart';
import '../../domain/address.dart';
import '../../domain/client.dart';
import '../../domain/consent.dart';
import '../../utils/clock.dart';
import '../db/database.dart';
import '../vault/field_crypto.dart';
import '_helpers.dart';

/// Single read/write surface for client records.
///
/// All sensitive fields go through [FieldCrypto] before touching the database.
/// Callers (UI, services) must NEVER access [HealthDb] directly for clients.
class ClientRepository {
  ClientRepository(this._db, this._crypto);

  final HealthDb _db;
  final FieldCrypto _crypto;
  final Uuid _uuid = const Uuid();

  /// Creates a client. Health and free notes are encrypted before insert.
  /// The mandatory consents (RGPD + disclaimer) MUST be present — the caller
  /// is responsible for collecting them.
  Future<Client> create(Client draft) async {
    if (!draft.consents.hasMandatory) {
      throw const ValidationError('client_consent_missing', 'consents');
    }
    final id = draft.id.isEmpty ? _uuid.v4() : draft.id;
    final now = nowEpochSeconds();
    final companion = await _toCompanion(
      draft.copyWith(id: id),
      isInsert: true,
      epochSeconds: now,
    );
    await _db.into(_db.clients).insert(companion);
    return (await getById(id))!;
  }

  Future<Client> update(Client client) async {
    final now = nowEpochSeconds();
    final companion = await _toCompanion(
      client,
      isInsert: false,
      epochSeconds: now,
    );
    await (_db.update(_db.clients)..where((t) => t.id.equals(client.id)))
        .write(companion);
    return (await getById(client.id))!;
  }

  /// Returns null if not found or already soft-deleted.
  Future<Client?> getById(String id) async {
    final row = await (_db.select(_db.clients)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    return _fromRow(row);
  }

  /// Stream the live list, sorted by lastName + firstName, excluding deleted.
  /// Sensitive fields are NOT decrypted in list views (perf + leak window).
  Stream<List<Client>> watchAll({String? query}) {
    final select = _db.select(_db.clients)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.lastName),
        (t) => OrderingTerm.asc(t.firstName),
      ]);
    if (query != null && query.trim().isNotEmpty) {
      final pattern = '%${query.trim()}%';
      select.where((t) =>
          t.lastName.like(pattern) |
          t.firstName.like(pattern) |
          t.email.like(pattern) |
          t.phone.like(pattern));
    }
    return select.watch().map(
          (rows) => rows.map(_fromRowLight).toList(growable: false),
        );
  }

  /// Soft delete — keeps the row for cascading checks. Use [purge] for the
  /// RGPD right-to-erasure flow.
  Future<void> softDelete(String id) async {
    final now = nowEpochSeconds();
    await (_db.update(_db.clients)..where((t) => t.id.equals(id))).write(
      ClientsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// Physical delete + cascade. Caller is responsible for purging attached
  /// files separately (the FK on attachments uses owner_id, not enforced).
  Future<void> purge(String id) async {
    await (_db.delete(_db.clients)..where((t) => t.id.equals(id))).go();
  }

  // -- mapping ---------------------------------------------------------------

  Future<ClientsCompanion> _toCompanion(
    Client client, {
    required bool isInsert,
    required int epochSeconds,
  }) async {
    final healthEncrypted = await encryptOptional(_crypto, client.healthNotes);
    final notesEncrypted = await encryptOptional(_crypto, client.notes);

    return ClientsCompanion(
      id: Value(client.id),
      civility: Value(client.civility),
      lastName: Value(client.lastName),
      firstName: Value(client.firstName),
      birthDateMs: Value(client.birthDate?.millisecondsSinceEpoch),
      phone: Value(client.phone),
      email: Value(client.email),
      profession: Value(client.profession),
      addressJson: Value(client.address.toJson()),
      businessJson: Value(client.business),
      profileJson: Value(client.profile),
      healthNotesEncrypted: healthEncrypted,
      notesEncrypted: notesEncrypted,
      consentRgpdAt: Value(client.consents.rgpdAt?.millisecondsSinceEpoch),
      consentDisclaimerAt:
          Value(client.consents.disclaimerAt?.millisecondsSinceEpoch),
      consentReminderAt:
          Value(client.consents.reminderAt?.millisecondsSinceEpoch),
      consentNewsletterAt:
          Value(client.consents.newsletterAt?.millisecondsSinceEpoch),
      updatedAt: Value(epochSeconds),
      createdAt: isInsert ? Value(epochSeconds) : const Value.absent(),
    );
  }

  /// Full mapping including decrypted sensitive fields. Use for detail view.
  Future<Client> _fromRow(ClientRow row) async {
    final health = row.healthNotesEncrypted == null
        ? ''
        : await _crypto.decryptString(row.healthNotesEncrypted!);
    final notes = row.notesEncrypted == null
        ? ''
        : await _crypto.decryptString(row.notesEncrypted!);
    return _baseFromRow(row).copyWith(healthNotes: health, notes: notes);
  }

  /// Light mapping for list views — does NOT decrypt sensitive fields.
  Client _fromRowLight(ClientRow row) => _baseFromRow(row);

  Client _baseFromRow(ClientRow row) => Client(
        id: row.id,
        civility: row.civility,
        lastName: row.lastName,
        firstName: row.firstName,
        birthDate: row.birthDateMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row.birthDateMs!),
        phone: row.phone,
        email: row.email,
        profession: row.profession,
        address: row.addressJson.isEmpty
            ? const Address()
            : Address.fromJson(row.addressJson),
        consents: ConsentSet(
          rgpdAt: _msToDate(row.consentRgpdAt),
          disclaimerAt: _msToDate(row.consentDisclaimerAt),
          reminderAt: _msToDate(row.consentReminderAt),
          newsletterAt: _msToDate(row.consentNewsletterAt),
        ),
        profile: row.profileJson,
        business: row.businessJson,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt * 1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt * 1000),
      );

  static DateTime? _msToDate(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}
