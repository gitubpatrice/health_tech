import 'package:drift/drift.dart';

import '../db/database.dart';

/// Cross-entity search across clients, animals, sessions, appointments.
///
/// Encrypted fields (health notes, free notes, session report, appointment
/// notes) are deliberately excluded — surfacing them would require
/// decrypting every row at query time AND would leak through any future
/// FTS5 index. The trade-off is "stable identifiers searchable, sensitive
/// content opaque to search". Practitioners filter by name / location /
/// kind / profession, then open the record to read the notes.
class GlobalSearchService {
  GlobalSearchService(this._db);

  final HealthDb _db;

  /// Returns a flat list of hits sorted by entity kind then by relevance
  /// proxy (alphabetical for now). The query is split on whitespace and
  /// every token must match at least one indexed column (AND semantics).
  Future<List<SearchHit>> search(
    String query, {
    int limit = 80,
    String appointmentDefaultTitle = 'Rendez-vous',
  }) async {
    // Strip d'abord les wildcards SQL, filtre ensuite : sinon "%" tout
    // seul (ou "%%%") deviendrait "%%" et matcherait toutes les lignes.
    final tokens = query
        .trim()
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(RegExp(r'[%_\\]'), ''))
        .where((t) => t.isNotEmpty)
        .map((t) => '%$t%')
        .toList(growable: false);
    if (tokens.isEmpty) return const [];

    final hits = <SearchHit>[];
    hits.addAll(await _searchClients(tokens, limit));
    hits.addAll(await _searchAnimals(tokens, limit));
    hits.addAll(await _searchSessions(tokens, limit));
    hits.addAll(
      await _searchAppointments(tokens, limit, appointmentDefaultTitle),
    );
    return hits;
  }

  Future<List<SearchHit>> _searchClients(List<String> tokens, int limit) async {
    final select = _db.select(_db.clients)..where((t) => t.deletedAt.isNull());
    for (final tk in tokens) {
      select.where(
        (t) =>
            t.lastName.like(tk) |
            t.firstName.like(tk) |
            t.email.like(tk) |
            t.phone.like(tk) |
            t.profession.like(tk),
      );
    }
    select
      ..orderBy([
        (t) => OrderingTerm.asc(t.lastName),
        (t) => OrderingTerm.asc(t.firstName),
      ])
      ..limit(limit);
    final rows = await select.get();
    return [
      for (final r in rows)
        SearchHit(
          kind: SearchHitKind.client,
          id: r.id,
          title: '${r.firstName} ${r.lastName}'.trim(),
          subtitle: [
            if ((r.profession ?? '').isNotEmpty) r.profession,
            if ((r.email ?? '').isNotEmpty) r.email,
            if ((r.phone ?? '').isNotEmpty) r.phone,
          ].whereType<String>().join(' · '),
        ),
    ];
  }

  Future<List<SearchHit>> _searchAnimals(List<String> tokens, int limit) async {
    final select = _db.select(_db.animals)..where((t) => t.deletedAt.isNull());
    for (final tk in tokens) {
      select.where(
        (t) =>
            t.name.like(tk) |
            t.breed.like(tk) |
            t.color.like(tk) |
            t.species.like(tk),
      );
    }
    select
      ..orderBy([(t) => OrderingTerm.asc(t.name)])
      ..limit(limit);
    final rows = await select.get();
    return [
      for (final r in rows)
        SearchHit(
          kind: SearchHitKind.animal,
          id: r.id,
          ownerId: r.clientId,
          title: r.name,
          subtitle: [
            r.species,
            if ((r.breed ?? '').isNotEmpty) r.breed,
            if ((r.color ?? '').isNotEmpty) r.color,
          ].whereType<String>().join(' · '),
        ),
    ];
  }

  Future<List<SearchHit>> _searchSessions(
    List<String> tokens,
    int limit,
  ) async {
    final select = _db.select(_db.sessions)..where((t) => t.deletedAt.isNull());
    for (final tk in tokens) {
      select.where(
        (t) => t.location.like(tk) | t.kind.like(tk) | t.motivesJson.like(tk),
      );
    }
    select
      ..orderBy([(t) => OrderingTerm.desc(t.startAt)])
      ..limit(limit);
    final rows = await select.get();
    return [
      for (final r in rows)
        SearchHit(
          kind: SearchHitKind.session,
          id: r.id,
          ownerId: r.clientId,
          title: r.kind,
          subtitle: [
            DateTime.fromMillisecondsSinceEpoch(r.startAt * 1000).toString(),
            if ((r.location ?? '').isNotEmpty) r.location,
          ].whereType<String>().join(' · '),
        ),
    ];
  }

  Future<List<SearchHit>> _searchAppointments(
    List<String> tokens,
    int limit,
    String defaultTitle,
  ) async {
    final select = _db.select(_db.appointments)
      ..where((t) => t.deletedAt.isNull());
    for (final tk in tokens) {
      select.where((t) => t.title.like(tk) | t.location.like(tk));
    }
    select
      ..orderBy([(t) => OrderingTerm.desc(t.startAt)])
      ..limit(limit);
    final rows = await select.get();
    return [
      for (final r in rows)
        SearchHit(
          kind: SearchHitKind.appointment,
          id: r.id,
          ownerId: r.clientId,
          title: r.title ?? defaultTitle,
          subtitle: [
            DateTime.fromMillisecondsSinceEpoch(r.startAt * 1000).toString(),
            if ((r.location ?? '').isNotEmpty) r.location,
          ].whereType<String>().join(' · '),
        ),
    ];
  }
}

enum SearchHitKind { client, animal, session, appointment }

class SearchHit {
  const SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    this.ownerId,
  });

  final SearchHitKind kind;
  final String id;

  /// For nested entities (animal / session / appointment owned by a client),
  /// the parent client id — lets the UI navigate straight to the client
  /// detail and pre-select the matching child.
  final String? ownerId;

  final String title;
  final String subtitle;
}
