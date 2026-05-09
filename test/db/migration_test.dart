import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/data/db/database.dart';

/// Migration baseline: every release should make sure that the schema
/// produced by `onCreate` matches what older clients with applied migrations
/// would converge to. Today we are at `schemaVersion = 1`, so this file just
/// pins the contract: tables, indexes, FTS and pragmas are all in place
/// after a fresh open. When `schemaVersion` bumps, add `from N → N+1` tests
/// here using `MigrationStrategy.onUpgrade` simulations.
void main() {
  group('Schema v1 baseline', () {
    test('all 7 tables are created', () async {
      final db = HealthDb.forTesting();
      addTearDown(db.close);
      final names = await db
          .customSelect(
            'SELECT name FROM sqlite_master '
            "WHERE type='table' AND name NOT LIKE 'sqlite_%' "
            "AND name NOT LIKE '%_fts%' "
            'ORDER BY name',
          )
          .map((row) => row.read<String>('name'))
          .get();
      expect(
        names,
        containsAll(<String>[
          'animals',
          'appointments',
          'attachments',
          'clients',
          'sessions',
          'tag_links',
          'tags',
        ]),
      );
    });

    test('expected indexes are present', () async {
      final db = HealthDb.forTesting();
      addTearDown(db.close);
      final names = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND name LIKE 'idx_%'",
          )
          .map((row) => row.read<String>('name'))
          .get();
      expect(
        names,
        containsAll(<String>[
          'idx_animals_client',
          'idx_sessions_client',
          'idx_sessions_animal',
          'idx_sessions_start',
          'idx_appointments_start',
          'idx_attachments_owner',
          'idx_taglinks_owner',
        ]),
      );
    });

    test('foreign_keys pragma is enabled', () async {
      final db = HealthDb.forTesting();
      addTearDown(db.close);
      final pragma = await db
          .customSelect('PRAGMA foreign_keys')
          .map((row) => row.read<int>('foreign_keys'))
          .getSingle();
      expect(pragma, 1);
    });

    test('clients table can be inserted and read', () async {
      final db = HealthDb.forTesting();
      addTearDown(db.close);
      await db.customStatement(
        'INSERT INTO clients(id, last_name, first_name, address_json, '
        'business_json, profile_json) '
        "VALUES('c-1','Doe','Jane','','','')",
      );
      final rows = await (db.select(db.clients)
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      expect(rows.length, 1);
      expect(rows.single.firstName, 'Jane');
    });
  });
}
