import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/report_template.dart';
import '../../utils/clock.dart';
import '../db/database.dart';
import '_helpers.dart';

/// CRUD live des modèles de comptes rendus (DB v6).
///
/// Pas de chiffrement champ-à-champ ici — un template est un canevas
/// générique sans PII. La table reste protégée par SQLCipher comme le
/// reste du coffre.
class ReportTemplateRepository {
  ReportTemplateRepository(this._db);

  final HealthDb _db;
  final Uuid _uuid = const Uuid();

  /// Stream live de tous les templates, tri stable : système d'abord
  /// (`is_system DESC`) puis par nom alphabétique. Permet à l'UI de
  /// proposer les canevas livrés avec l'app en tête de liste.
  Stream<List<ReportTemplate>> watchAll() {
    final select = _db.select(_db.reportTemplates)
      ..orderBy([
        (t) => OrderingTerm.desc(t.isSystem),
        (t) => OrderingTerm.asc(t.name),
      ]);
    return select.watch().map(
      (rows) => rows.map(_fromRow).toList(growable: false),
    );
  }

  /// Stream live filtré par `kind`. Les templates `other` et `distance`
  /// sont toujours inclus, car polyvalents — on n'a pas envie d'imposer
  /// au praticien de retourner dans Réglages pour les retrouver depuis
  /// le formulaire de séance.
  Stream<List<ReportTemplate>> watchByKind(String kind) {
    final select = _db.select(_db.reportTemplates)
      ..where(
        (t) =>
            t.kind.equals(kind) |
            t.kind.equals(ReportTemplateKind.other) |
            t.kind.equals(ReportTemplateKind.distance),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.isSystem),
        (t) => OrderingTerm.asc(t.name),
      ]);
    return select.watch().map(
      (rows) => rows.map(_fromRow).toList(growable: false),
    );
  }

  Future<ReportTemplate?> getById(String id) async {
    final row = await (_db.select(
      _db.reportTemplates,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<ReportTemplate> create(ReportTemplate draft) async {
    final id = draft.id.isEmpty ? _uuid.v4() : draft.id;
    final now = nowEpochSeconds();
    await _db
        .into(_db.reportTemplates)
        .insert(
          ReportTemplatesCompanion(
            id: Value(id),
            name: Value(draft.name),
            kind: Value(draft.kind),
            sectionsJson: Value(_sectionsToJson(draft.sections)),
            isSystem: Value(draft.isSystem),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return (await getById(id))!;
  }

  Future<ReportTemplate> update(ReportTemplate template) async {
    final now = nowEpochSeconds();
    await (_db.update(
      _db.reportTemplates,
    )..where((t) => t.id.equals(template.id))).write(
      ReportTemplatesCompanion(
        name: Value(template.name),
        kind: Value(template.kind),
        sectionsJson: Value(_sectionsToJson(template.sections)),
        // `isSystem` est volontairement immuable côté UI : seul le seed
        // peut produire un template système. On ne le réécrit pas ici
        // pour éviter qu'un copyWith() ne contamine la table.
        updatedAt: Value(now),
      ),
    );
    return (await getById(template.id))!;
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.reportTemplates)..where((t) => t.id.equals(id))).go();
    // Suppression d'un template système = donnée potentiellement
    // sensible (nom de canevas qui revèle une orientation de pratique).
    // SQLCipher écrit en WAL : tant que le checkpoint n'est pas
    // déclenché, les bytes restent dans `health.db-wal` (toujours
    // chiffrés, mais contre-disant le claim « irréversible »). On
    // force un `TRUNCATE` checkpoint après chaque delete pour aligner
    // l'observable et le claim — audit v1.6.0 F6. Best-effort : si
    // le checkpoint échoue (lock concurrent), c'est non-bloquant.
    try {
      await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');
    } on Object {
      // ignore — au prochain lock, `db.close()` checkpoint de toute façon.
    }
  }

  /// Existe-t-il au moins UN template système ?
  ///
  /// Utilisé par `ReportTemplateSeed` pour décider d'injecter ou non les
  /// canevas par défaut. Idempotence forte : si l'utilisateur supprime un
  /// template système, il ne revient pas au prochain unlock.
  Future<bool> hasAnySystemTemplate() async {
    final query = _db.selectOnly(_db.reportTemplates)
      ..addColumns([_db.reportTemplates.id])
      ..where(_db.reportTemplates.isSystem.equals(true))
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row != null;
  }

  /// Insertion en masse des templates système dans **une seule
  /// transaction Drift** + re-check `hasAnySystemTemplate()` à l'intérieur
  /// de la transaction pour éviter la race au double-unlock (audit v1.6.0
  /// P1 + F4). Si un seed concurrent a déjà inséré la palette, le 2nd
  /// appel sort sans rien faire — pas de doublons.
  ///
  /// Bénéfice perf : un seul fsync WAL au lieu de N. Sur S9/POCO bas-de-
  /// gamme post-unlock, gain mesuré ~5-10× sur la fenêtre 200-500 ms.
  Future<void> seedSystemDefaults(List<ReportTemplate> drafts) async {
    if (drafts.isEmpty) return;
    await _db.transaction(() async {
      if (await hasAnySystemTemplate()) {
        // Un seed concurrent a gagné la course — ou l'utilisateur avait
        // déjà fait ses templates. Soit, on sort.
        return;
      }
      final now = nowEpochSeconds();
      for (final draft in drafts) {
        final id = draft.id.isEmpty ? _uuid.v4() : draft.id;
        await _db
            .into(_db.reportTemplates)
            .insert(
              ReportTemplatesCompanion(
                id: Value(id),
                name: Value(draft.name),
                kind: Value(draft.kind),
                sectionsJson: Value(_sectionsToJson(draft.sections)),
                isSystem: Value(draft.isSystem),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      }
    });
  }

  // -- mapping ---------------------------------------------------------------

  /// Force la conversion `Map<String, dynamic>` (JsonMapConverter) →
  /// `Map<String, String>` exposée par le domaine. On filtre toute valeur
  /// non-String pour ne pas crasher si un futur format glisse un type
  /// inattendu (ex : import depuis un export futur).
  Map<String, dynamic> _sectionsToJson(Map<String, String> sections) {
    return <String, dynamic>{
      for (final e in sections.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
  }

  Map<String, String> _sectionsFromJson(Map<String, dynamic> json) {
    return <String, String>{
      for (final e in json.entries)
        if (e.value is String && (e.value as String).isNotEmpty)
          e.key: e.value as String,
    };
  }

  ReportTemplate _fromRow(ReportTemplateRow row) => ReportTemplate(
    id: row.id,
    name: row.name,
    kind: row.kind,
    sections: row.sectionsJson.isEmpty
        ? const <String, String>{}
        : _sectionsFromJson(row.sectionsJson),
    isSystem: row.isSystem,
    createdAt: secondsToDate(row.createdAt),
    updatedAt: secondsToDate(row.updatedAt),
  );
}
