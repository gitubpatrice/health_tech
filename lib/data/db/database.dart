import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

import 'converters.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Clients,
    Animals,
    Sessions,
    Appointments,
    Attachments,
    Tags,
    TagLinks,
    ReportTemplates,
  ],
)
class HealthDb extends _$HealthDb {
  HealthDb(super.executor);

  /// **À ne JAMAIS bumper sans bumper aussi
  /// `BackupService._maxSupportedDbUserVersion`** — sinon les utilisateurs
  /// ne peuvent plus restaurer leur propre `.htbk` (audit C1 v1.5.2).
  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
      await _createFts();
    },
    onUpgrade: (m, from, to) async {
      // v1 → v2 : colonne `kind` sur clients (individual / business).
      if (from < 2) {
        await m.addColumn(clients, clients.kind);
      }
      // v2 → v3 : indices appointments(client_id) / appointments(animal_id) +
      // composites partiels sur (start_at) WHERE deleted_at IS NULL pour que
      // watchUpcoming / watchInRange fasse un range scan plutôt qu'un full
      // table scan à 1000+ rdv.
      if (from < 3) {
        await _createIndexesV3();
      }
      // v3 → v4 : colonnes de synchronisation agenda sur sessions. Nullable
      // sur toutes les rows existantes — aucun event à recréer rétrospectivement.
      if (from < 4) {
        await m.addColumn(sessions, sessions.externalCalendarId);
        await m.addColumn(sessions, sessions.externalCalendarEventId);
      }
      // v4 → v5 : chiffrement au champ du nom de fichier attachment.
      // La colonne legacy `filename` reste pour ne pas casser les rows
      // existantes (lecture rétrocompatible) ; toute nouvelle écriture
      // pose `filenameEncrypted` et vide `filename`. La migration des
      // anciennes rows se fait paresseusement à la première lecture
      // (voir AttachmentRepository._fromRow).
      if (from < 5) {
        await m.addColumn(attachments, attachments.filenameEncrypted);
      }
      // v5 → v6 : table `report_templates` (modèles de comptes rendus).
      // Pure création de table — aucune migration de données sur les tables
      // existantes (les champs cosmétiques v1.6.0 — source contact /
      // contact d'urgence / hygiène de vie / vétérinaire structuré /
      // vaccination — passent par les JSON déjà en place
      // `clients.profile_json` et `animals.identifiers_json`).
      if (from < 6) {
        await m.createTable(reportTemplates);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON;');
      await customStatement('PRAGMA journal_mode = WAL;');
      // FULL plutôt que NORMAL : pour des données santé, on accepte ~10%
      // de perte de perf en écriture pour garantir qu'aucune transaction
      // n'est marquée durable sans avoir réellement été flushée sur disque
      // (NORMAL peut perdre les dernières transactions en cas de power-loss).
      await customStatement('PRAGMA synchronous = FULL;');
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
    // v3 indices intégrés dès la création (nouveau coffre = directement v3).
    await _createIndexesV3();
  }

  /// Indices ajoutés en v3 : `appointments` n'avait que `start_at`, ce qui
  /// suffisait au début mais devient un full scan dès qu'on filtre par
  /// `client_id` ou `animal_id` (PurgeService.softDeleteAnimal,
  /// agenda.watchByClient, ...). Le composite partiel `(start_at) WHERE
  /// deleted_at IS NULL` accélère watchUpcoming / watchInRange à 1000+ rdv.
  Future<void> _createIndexesV3() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_appointments_client '
      'ON appointments(client_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_appointments_animal '
      'ON appointments(animal_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_appointments_active_start '
      'ON appointments(start_at) WHERE deleted_at IS NULL;',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_active_start '
      'ON sessions(start_at) WHERE deleted_at IS NULL;',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_client_start '
      'ON sessions(client_id, start_at);',
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

  /// Opens the encrypted database, keyed with the raw 32-byte VEK.
  ///
  /// The hex projection of the VEK only exists inside the SQLCipher `setup`
  /// callback. Outside of it, no String holds the key material — the
  /// caller passes the raw [Uint8List] which can be wiped after the call.
  /// This shrinks the lifetime of an immutable, GC-bound copy of the key
  /// (Dart `String`s cannot be zeroed) to a single `db.execute` call.
  static Future<HealthDb> open({required Uint8List vek}) async {
    if (vek.length != 32) {
      throw ArgumentError.value(
        vek.length,
        'vek.length',
        'SQLCipher raw key must be exactly 32 bytes',
      );
    }
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();

    final dir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(dir.path, 'db'));
    if (!dbDir.existsSync()) {
      await dbDir.create(recursive: true);
    }
    final dbFile = File(p.join(dbDir.path, 'health.db'));

    // Take a defensive copy so the caller can wipe its own buffer the
    // moment open() returns, without the setup callback (which may run
    // later, on the SQLite background isolate) seeing zeroed bytes.
    final keyCopy = Uint8List.fromList(vek);

    final executor = NativeDatabase.createInBackground(
      dbFile,
      // CRITICAL: NativeDatabase.createInBackground spawns its own isolate
      // and that isolate does NOT inherit the open.overrideFor() set in
      // main(). Without this re-registration, the worker isolate falls back
      // to the system libsqlite3.so (which doesn't ship on Android) and
      // every DB-backed screen crashes with "libsqlite3.so not found".
      isolateSetup: () async {
        sqlite3_open.open.overrideFor(
          sqlite3_open.OperatingSystem.android,
          openCipherOnAndroid,
        );
      },
      setup: (db) {
        db.config.doubleQuotedStringLiterals = false;
        // Build the hex string strictly inside the callback. It becomes
        // GC-eligible as soon as `db.execute` returns. We can't zero the
        // String itself (Dart immutability) but we can avoid keeping it
        // referenced anywhere reachable afterwards.
        final buf = StringBuffer();
        for (final b in keyCopy) {
          buf.write(b.toRadixString(16).padLeft(2, '0'));
        }
        db.execute("PRAGMA key = \"x'${buf.toString()}'\";");
        db.execute('PRAGMA cipher_memory_security = ON;');
        // Wipe the local key copy now that SQLCipher has internalised it.
        keyCopy.fillRange(0, keyCopy.length, 0);
      },
    );
    return HealthDb(executor);
  }

  /// In-memory database for tests.
  static HealthDb forTesting() => HealthDb(NativeDatabase.memory());
}
