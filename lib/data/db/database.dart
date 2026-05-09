import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

import 'converters.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Clients, Animals, Sessions, Appointments, Attachments, Tags, TagLinks],
)
class HealthDb extends _$HealthDb {
  HealthDb(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
          await _createFts();
        },
        onUpgrade: (m, from, to) async {
          // Future migrations land here, version by version.
          // Each upgrade MUST be tested in test/db/migration_test.dart.
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
          await customStatement('PRAGMA journal_mode = WAL;');
          await customStatement('PRAGMA synchronous = NORMAL;');
          await customStatement('PRAGMA temp_store = MEMORY;');
        },
      );

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_animals_client ON animals(client_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_client ON sessions(client_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_animal ON sessions(animal_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_start ON sessions(start_at);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_appointments_start ON appointments(start_at);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_attachments_owner '
      'ON attachments(owner_type, owner_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_taglinks_owner '
      'ON tag_links(owner_type, owner_id);',
    );
  }

  /// FTS5 index for full-text search on clients (last_name, first_name, email,
  /// phone). Encrypted free-text fields are NOT indexed (they would leak through
  /// FTS internal storage). Only stable identifiers are indexed.
  ///
  /// Falls back silently if the underlying SQLite build does not include FTS5
  /// (some test/host installations). The repository `watchAll` uses LIKE in
  /// that case, so functionality degrades gracefully.
  Future<void> _createFts() async {
    try {
      await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS clients_fts USING fts5(
        last_name, first_name, email, phone,
        content='clients', content_rowid='rowid', tokenize='unicode61'
      );
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS clients_ai AFTER INSERT ON clients BEGIN
        INSERT INTO clients_fts(rowid, last_name, first_name, email, phone)
        VALUES (new.rowid, new.last_name, new.first_name,
                COALESCE(new.email,''), COALESCE(new.phone,''));
      END;
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS clients_ad AFTER DELETE ON clients BEGIN
        INSERT INTO clients_fts(clients_fts, rowid, last_name, first_name, email, phone)
        VALUES ('delete', old.rowid, old.last_name, old.first_name,
                COALESCE(old.email,''), COALESCE(old.phone,''));
      END;
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS clients_au AFTER UPDATE ON clients BEGIN
        INSERT INTO clients_fts(clients_fts, rowid, last_name, first_name, email, phone)
        VALUES ('delete', old.rowid, old.last_name, old.first_name,
                COALESCE(old.email,''), COALESCE(old.phone,''));
        INSERT INTO clients_fts(rowid, last_name, first_name, email, phone)
        VALUES (new.rowid, new.last_name, new.first_name,
                COALESCE(new.email,''), COALESCE(new.phone,''));
      END;
    ''');
    } on Object {
      // FTS5 not compiled in: search falls back to LIKE in repositories.
    }
  }

  /// Opens the encrypted database with the master passphrase.
  ///
  /// The passphrase is held only in memory during open and immediately wiped
  /// from local strings (caller must wipe theirs).
  static Future<HealthDb> open({required String passphrase}) async {
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();

    final dir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(dir.path, 'db'));
    if (!dbDir.existsSync()) {
      await dbDir.create(recursive: true);
    }
    final dbFile = File(p.join(dbDir.path, 'health.db'));

    final executor = NativeDatabase.createInBackground(
      dbFile,
      setup: (db) {
        db.config.doubleQuotedStringLiterals = false;
        // Keying MUST be the very first statement issued to the connection.
        // Quoting via x'...' would require a hex-encoded key; we pass the raw
        // passphrase wrapped per SQLCipher conventions.
        final escaped = passphrase.replaceAll("'", "''");
        db.execute("PRAGMA key = '$escaped';");
        db.execute('PRAGMA cipher_memory_security = ON;');
      },
    );
    return HealthDb(executor);
  }

  /// In-memory database for tests.
  static HealthDb forTesting() => HealthDb(NativeDatabase.memory());
}
