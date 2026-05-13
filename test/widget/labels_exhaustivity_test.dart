import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/domain/lifestyle.dart';
import 'package:health_tech/domain/report_template.dart';
import 'package:health_tech/features/templates/templates_l10n.dart';
import 'package:health_tech/l10n/generated/app_localizations.dart';

/// Garde-fou (audit v1.6.0 C7) : si on ajoute une valeur à `Lifestyle.*`,
/// `ContactSource.all` ou `ReportTemplateKind.all` sans étendre la mapping
/// l10n dans `templates_l10n.dart`, on tomberait silencieusement sur
/// `lifestyleUnspecified` / `contactSourceUnspecified` / la valeur brute
/// côté UI. Ce test compare le label produit à chacun des cas connus.
///
/// La logique : pour CHAQUE valeur d'enum-like, le label doit
///   1. être non vide,
///   2. différer du label « non renseigné » (sinon = mapping oublié).
///
/// Volontairement exécuté contre les deux locales FR + EN pour attraper
/// un oubli d'une seule des deux ARB.
void main() {
  for (final localeCode in const ['fr', 'en']) {
    group('Exhaustivité l10n — locale $localeCode', () {
      late AppL10n l10n;

      setUpAll(() async {
        l10n = await AppL10n.delegate.load(Locale(localeCode));
      });

      test('Lifestyle.smokerValues — tous les libellés mappés', () {
        final unspecified = l10n.lifestyleUnspecified;
        for (final v in Lifestyle.smokerValues) {
          final label = lifestyleLabel(l10n, v);
          expect(label, isNotEmpty);
          expect(
            label,
            isNot(unspecified),
            reason: 'Valeur "$v" non mappée dans lifestyleLabel ($localeCode)',
          );
        }
      });

      test('Lifestyle.sportValues — tous les libellés mappés', () {
        final unspecified = l10n.lifestyleUnspecified;
        for (final v in Lifestyle.sportValues) {
          expect(lifestyleLabel(l10n, v), isNot(unspecified));
        }
      });

      test('Lifestyle.sleepValues — tous les libellés mappés', () {
        final unspecified = l10n.lifestyleUnspecified;
        for (final v in Lifestyle.sleepValues) {
          expect(lifestyleLabel(l10n, v), isNot(unspecified));
        }
      });

      test('Lifestyle.stressValues — tous les libellés mappés', () {
        final unspecified = l10n.lifestyleUnspecified;
        for (final v in Lifestyle.stressValues) {
          expect(lifestyleLabel(l10n, v), isNot(unspecified));
        }
      });

      test('Lifestyle.dietValues — tous les libellés mappés', () {
        final unspecified = l10n.lifestyleUnspecified;
        for (final v in Lifestyle.dietValues) {
          expect(lifestyleLabel(l10n, v), isNot(unspecified));
        }
      });

      test('ContactSource.all — tous les libellés mappés', () {
        final unspecified = l10n.contactSourceUnspecified;
        for (final v in ContactSource.all) {
          final label = contactSourceLabel(l10n, v);
          expect(label, isNotEmpty);
          expect(
            label,
            isNot(unspecified),
            reason:
                'Source "$v" non mappée dans contactSourceLabel ($localeCode)',
          );
        }
      });

      test('ReportTemplateKind.all — tous les libellés mappés', () {
        for (final v in ReportTemplateKind.all) {
          final label = reportTemplateKindLabel(l10n, v);
          // Le label ne doit JAMAIS retomber sur la valeur brute
          // (kind == label signifie le `default:` du switch).
          expect(label, isNot(v));
          expect(label, isNotEmpty);
        }
      });
    });
  }
}
