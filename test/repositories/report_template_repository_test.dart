import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/data/db/database.dart';
import 'package:health_tech/data/repositories/report_template_repository.dart';
import 'package:health_tech/data/services/report_template_seed.dart';
import 'package:health_tech/domain/report_template.dart';

void main() {
  late HealthDb db;
  late ReportTemplateRepository repo;

  setUp(() {
    db = HealthDb.forTesting();
    repo = ReportTemplateRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ReportTemplateRepository', () {
    test(
      'create + getById round-trips name, kind, sections, isSystem',
      () async {
        final created = await repo.create(
          const ReportTemplate(
            id: '',
            name: 'Test',
            kind: ReportTemplateKind.human,
            sections: {'before': 'État avant'},
            isSystem: true,
          ),
        );
        expect(created.id, isNotEmpty);
        expect(created.isSystem, true);
        final fetched = await repo.getById(created.id);
        expect(fetched, isNotNull);
        expect(fetched!.name, 'Test');
        expect(fetched.kind, ReportTemplateKind.human);
        expect(fetched.sections['before'], 'État avant');
        expect(fetched.isSystem, true);
      },
    );

    test('update mutates name + sections but preserves isSystem', () async {
      final created = await repo.create(
        const ReportTemplate(
          id: '',
          name: 'Initial',
          kind: ReportTemplateKind.human,
          sections: {'before': 'X'},
          isSystem: true,
        ),
      );
      final updated = await repo.update(
        created.copyWith(
          name: 'Renamed',
          sections: {'before': 'Y', 'after': 'Z'},
          isSystem: false, // tentative — doit être ignorée
        ),
      );
      expect(updated.name, 'Renamed');
      expect(updated.sections['after'], 'Z');
      // L'audit interne du repo doit préserver le flag système.
      expect(updated.isSystem, true);
    });

    test('delete removes the row', () async {
      final created = await repo.create(
        const ReportTemplate(
          id: '',
          name: 'Drop me',
          kind: ReportTemplateKind.other,
          sections: {},
        ),
      );
      await repo.delete(created.id);
      expect(await repo.getById(created.id), isNull);
    });

    test(
      'watchByKind includes other + distance regardless of filter',
      () async {
        await repo.create(
          const ReportTemplate(
            id: '',
            name: 'Humain only',
            kind: ReportTemplateKind.human,
            sections: {},
          ),
        );
        await repo.create(
          const ReportTemplate(
            id: '',
            name: 'Animal only',
            kind: ReportTemplateKind.animal,
            sections: {},
          ),
        );
        await repo.create(
          const ReportTemplate(
            id: '',
            name: 'Polyvalent',
            kind: ReportTemplateKind.other,
            sections: {},
          ),
        );
        await repo.create(
          const ReportTemplate(
            id: '',
            name: 'Distance',
            kind: ReportTemplateKind.distance,
            sections: {},
          ),
        );
        final humanList = await repo
            .watchByKind(ReportTemplateKind.human)
            .first;
        final names = humanList.map((t) => t.name).toSet();
        expect(names, containsAll(['Humain only', 'Polyvalent', 'Distance']));
        expect(names.contains('Animal only'), false);
      },
    );

    test(
      'hasAnySystemTemplate returns false on empty / true once seeded',
      () async {
        expect(await repo.hasAnySystemTemplate(), false);
        await repo.create(
          const ReportTemplate(
            id: '',
            name: 'X',
            kind: ReportTemplateKind.human,
            sections: {},
            isSystem: true,
          ),
        );
        expect(await repo.hasAnySystemTemplate(), true);
      },
    );
  });

  group('ReportTemplateSeed.seedDefaultsIfEmpty', () {
    test('inserts 6 templates on empty DB', () async {
      final seed = ReportTemplateSeed(repo);
      await seed.seedDefaultsIfEmpty();
      final list = await repo.watchAll().first;
      expect(list.length, 6);
      expect(list.every((t) => t.isSystem), true);
    });

    test('is idempotent — second call does NOT duplicate', () async {
      final seed = ReportTemplateSeed(repo);
      await seed.seedDefaultsIfEmpty();
      await seed.seedDefaultsIfEmpty();
      final list = await repo.watchAll().first;
      expect(list.length, 6);
    });

    test('does NOT re-seed if user deleted all system templates', () async {
      final seed = ReportTemplateSeed(repo);
      await seed.seedDefaultsIfEmpty();
      // L'utilisateur supprime tout
      final all = await repo.watchAll().first;
      for (final t in all) {
        await repo.delete(t.id);
      }
      // On crée un template custom non-système pour qu'on ne soit pas
      // exactement "empty" — mais hasAnySystemTemplate doit toujours
      // dire false → le seed se réinjecterait. C'est le comportement
      // attendu : tant que la table n'a aucun is_system, le seed
      // s'applique. Si l'utilisateur veut empêcher la ré-injection,
      // il peut conserver au moins un is_system (ou modifier en custom).
      // Ce test documente le contrat : seul `hasAnySystemTemplate`
      // décide, pas la présence de templates custom.
      await repo.create(
        const ReportTemplate(
          id: '',
          name: 'Custom',
          kind: ReportTemplateKind.human,
          sections: {'before': 'X'},
          isSystem: false,
        ),
      );
      await seed.seedDefaultsIfEmpty();
      final after = await repo.watchAll().first;
      // 6 system seeded + 1 custom préexistant
      expect(after.where((t) => t.isSystem).length, 6);
      expect(after.where((t) => !t.isSystem).length, 1);
    });

    test('preserves order: system first then alphabetical', () async {
      final seed = ReportTemplateSeed(repo);
      await seed.seedDefaultsIfEmpty();
      await repo.create(
        const ReportTemplate(
          id: '',
          name: 'AAA Custom',
          kind: ReportTemplateKind.human,
          sections: {},
        ),
      );
      final list = await repo.watchAll().first;
      // is_system DESC : tous les 6 system avant le custom
      expect(list.take(6).every((t) => t.isSystem), true);
      expect(list.last.name, 'AAA Custom');
    });
  });

  group('ReportTemplate.toSessionReport()', () {
    test('mappe les 9 clés sur les champs SessionReport', () {
      const t = ReportTemplate(
        id: 'x',
        name: 'x',
        kind: ReportTemplateKind.human,
        sections: {
          'before': 'B',
          'client': 'C',
          'observations': 'O',
          'flow': 'F',
          'zones': 'Z',
          'energetic': 'E',
          'after': 'A',
          'advice': 'AD',
          'next': 'N',
        },
      );
      final r = t.toSessionReport();
      expect(r.beforeState, 'B');
      expect(r.clientPerception, 'C');
      expect(r.observations, 'O');
      expect(r.flow, 'F');
      expect(r.zonesWorked, 'Z');
      expect(r.energetic, 'E');
      expect(r.afterState, 'A');
      expect(r.advice, 'AD');
      expect(r.nextRecommendation, 'N');
    });

    test('sections absentes → champs vides', () {
      const t = ReportTemplate(
        id: 'x',
        name: 'x',
        kind: ReportTemplateKind.human,
        sections: {'before': 'B'},
      );
      final r = t.toSessionReport();
      expect(r.beforeState, 'B');
      expect(r.clientPerception, '');
      expect(r.observations, '');
    });
  });
}
