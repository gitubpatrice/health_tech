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

  /// Disponibilité de la table virtuelle `clients_fts` (FTS5). Mémoïsée
  /// au premier appel : si SQLite n'a pas FTS5 compilé (tests host,
  /// vieux Android), on retombe définitivement sur le path LIKE.
  bool? _ftsAvailable;

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
    await (_db.update(
      _db.clients,
    )..where((t) => t.id.equals(client.id))).write(companion);
    return (await getById(client.id))!;
  }

  /// Returns null if not found or already soft-deleted.
  Future<Client?> getById(String id) async {
    final row = await (_db.select(
      _db.clients,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (row == null) return null;
    return _fromRow(row);
  }

  /// Stream the live list, sorted by lastName + firstName, excluding deleted.
  /// Sensitive fields are NOT decrypted in list views (perf + leak window).
  ///
  /// **Audit perf H4** — Si une [query] est fournie ET que FTS5 est
  /// disponible (créé en `_createFts`), on utilise `MATCH` plutôt que
  /// `LIKE` : 10-50× plus rapide sur grand jeu (5000+ clients), et
  /// indépendant du fait que la query soit en début / milieu / fin
  /// de mot. Fallback `LIKE` si FTS5 absent (SQLite host non compilé
  /// avec, certains anciens devices, environnements de test).
  Stream<List<Client>> watchAll({String? query}) {
    final trimmed = query?.trim() ?? '';
    if (trimmed.isEmpty) {
      return _watchLikeOrAll(null);
    }
    // Stream-of-stream : on probe FTS5 une seule fois puis on bascule
    // sur le bon path. Le `asyncExpand` retourne directement le stream
    // ciblé, qui demeure live (Drift met à jour à chaque update).
    return Stream.fromFuture(_isFtsAvailable()).asyncExpand(
      (hasFts) => hasFts ? _watchFts(trimmed) : _watchLikeOrAll(trimmed),
    );
  }

  /// Pure-LIKE path (fallback). Quand `query == null` retourne TOUT
  /// (ordering / soft-delete uniquement).
  Stream<List<Client>> _watchLikeOrAll(String? query) {
    final select = _db.select(_db.clients)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.lastName),
        (t) => OrderingTerm.asc(t.firstName),
      ]);
    if (query != null && query.isNotEmpty) {
      final pattern = '%$query%';
      select.where(
        (t) =>
            t.lastName.like(pattern) |
            t.firstName.like(pattern) |
            t.email.like(pattern) |
            t.phone.like(pattern),
      );
    }
    return select.watch().map(
      (rows) => rows.map(_fromRowLight).toList(growable: false),
    );
  }

  /// FTS5 path. Probe `_ftsAvailable` est déjà true lorsqu'on entre ici.
  /// On combine MATCH + LIKE pour garder l'UX naturelle (matches en
  /// milieu de mot via LIKE, accélération via FTS5 pour les prefixes).
  Stream<List<Client>> _watchFts(String query) {
    final ftsExpr = _ftsExpression(query);
    final pattern = '%$query%';
    return _db
        .customSelect(
          '''
      SELECT c.* FROM clients c
      WHERE c.deleted_at IS NULL
        AND (
          EXISTS (
            SELECT 1 FROM clients_fts f
            WHERE f.rowid = c.rowid AND clients_fts MATCH ?
          )
          OR c.last_name LIKE ?
          OR c.first_name LIKE ?
          OR COALESCE(c.email,'') LIKE ?
          OR COALESCE(c.phone,'') LIKE ?
        )
      ORDER BY c.last_name COLLATE NOCASE ASC,
               c.first_name COLLATE NOCASE ASC
      ''',
          variables: [
            Variable<String>(ftsExpr),
            Variable<String>(pattern),
            Variable<String>(pattern),
            Variable<String>(pattern),
            Variable<String>(pattern),
          ],
          readsFrom: {_db.clients},
        )
        .watch()
        .map(
          (rows) => rows
              .map((row) => _db.clients.map(row.data))
              .map(_fromRowLight)
              .toList(growable: false),
        );
  }

  /// Probe une seule fois la présence de la table virtuelle `clients_fts`.
  /// Le résultat est mémoïsé — pas de coût récurrent.
  Future<bool> _isFtsAvailable() async {
    final cached = _ftsAvailable;
    if (cached != null) return cached;
    try {
      await _db
          .customSelect('SELECT 1 FROM clients_fts WHERE rowid = 0 LIMIT 1')
          .get();
      _ftsAvailable = true;
    } on Object {
      _ftsAvailable = false;
    }
    return _ftsAvailable!;
  }

  /// Construit une expression FTS5 sûre depuis le texte utilisateur :
  /// - tokens séparés par espaces ;
  /// - caractères réservés FTS5 (`"^*:`) supprimés (anti-injection) ;
  /// - chaque token >= 2 caractères reçoit un `*` final (prefix match) ;
  /// - tokens trop courts sont ignorés (FTS5 les rejette par défaut).
  static String _ftsExpression(String raw) {
    final tokens = raw
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(RegExp(r'["\^\*:]'), ''))
        .where((t) => t.length >= 2)
        .map((t) => '$t*')
        .toList();
    if (tokens.isEmpty) {
      // Si l'utilisateur n'a tapé que 1 caractère ou des séparateurs,
      // on revient à un terme vide qui matchera tout ; couplé au LIKE
      // dans le SQL ci-dessus, on garde une UX naturelle.
      return '*';
    }
    return tokens.join(' ');
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
      kind: Value(client.kind),
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
      consentDisclaimerAt: Value(
        client.consents.disclaimerAt?.millisecondsSinceEpoch,
      ),
      consentReminderAt: Value(
        client.consents.reminderAt?.millisecondsSinceEpoch,
      ),
      consentNewsletterAt: Value(
        client.consents.newsletterAt?.millisecondsSinceEpoch,
      ),
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
    kind: row.kind,
    civility: row.civility,
    lastName: row.lastName,
    firstName: row.firstName,
    birthDate: msToDate(row.birthDateMs),
    phone: row.phone,
    email: row.email,
    profession: row.profession,
    address: row.addressJson.isEmpty
        ? const Address()
        : Address.fromJson(row.addressJson),
    consents: ConsentSet(
      rgpdAt: msToDate(row.consentRgpdAt),
      disclaimerAt: msToDate(row.consentDisclaimerAt),
      reminderAt: msToDate(row.consentReminderAt),
      newsletterAt: msToDate(row.consentNewsletterAt),
    ),
    profile: row.profileJson,
    business: row.businessJson,
    createdAt: secondsToDate(row.createdAt),
    updatedAt: secondsToDate(row.updatedAt),
  );
}
