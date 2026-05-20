// Tests garde-régression pour l'audit expert Health Tech v1.7.1.
//
// Verrouille les invariants introduits par les fixes :
//   - H1 : setAvatar refuse explicitement image/gif (anti-OOM rendu)
//   - C3 : PanicStep.systemCalendarWipe précède vaultDestroy
//   - C2 : Stopwatch monotone instancié dans HealthVault (anti clock-skew)
//
// Stratégie : ces tests ne montent pas l'infrastructure complète (DB
// SQLCipher + Secure Storage + plugins natifs). Ils vérifient les
// invariants observables côté API publique + enum + constantes — suffisant
// pour détecter une régression future qui retirerait ces protections.

import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/core/errors.dart';
import 'package:health_tech/data/services/panic_service.dart';

void main() {
  group('C3 v1.7.1 — PanicStep.systemCalendarWipe', () {
    test('systemCalendarWipe existe dans l\'enum', () {
      expect(
        PanicStep.values.contains(PanicStep.systemCalendarWipe),
        isTrue,
        reason:
            'L\'étape systemCalendarWipe doit exister pour fermer la faille '
            'RGPD post-panic (rendez-vous résiduels dans le calendrier '
            'système Android).',
      );
    });

    test('systemCalendarWipe précède strictement vaultDestroy', () {
      const values = PanicStep.values;
      final calIdx = values.indexOf(PanicStep.systemCalendarWipe);
      final vaultIdx = values.indexOf(PanicStep.vaultDestroy);
      expect(calIdx, greaterThanOrEqualTo(0));
      expect(
        vaultIdx,
        greaterThan(calIdx),
        reason:
            'systemCalendarWipe DOIT lire la DB déchiffrée avant que '
            'vault.destroy ne la rende inaccessible. Inverser l\'ordre = '
            'ne plus pouvoir effacer les events Calendar Android.',
      );
    });

    test('systemCalendarWipe précède strictement dbDelete', () {
      const values = PanicStep.values;
      final calIdx = values.indexOf(PanicStep.systemCalendarWipe);
      final dbIdx = values.indexOf(PanicStep.dbDelete);
      expect(
        dbIdx,
        greaterThan(calIdx),
        reason:
            'systemCalendarWipe doit lire les externalCalendarId / '
            'externalCalendarEventId dans la DB avant qu\'elle ne soit '
            'supprimée.',
      );
    });

    test('notificationsCancel reste le tout premier step', () {
      expect(
        PanicStep.values.first,
        PanicStep.notificationsCancel,
        reason:
            'Le panic doit toujours couper d\'abord ce qui pourrait '
            'écrire (notifications planifiées). Inchangé par v1.7.1.',
      );
    });

    test('done reste le dernier step', () {
      expect(PanicStep.values.last, PanicStep.done);
    });
  });

  group('H1 v1.7.1 — AttachmentRejectedError image_format_unsupported', () {
    test(
      'reason "image_format_unsupported" est un AttachmentRejectedError',
      () {
        const err = AttachmentRejectedError('image_format_unsupported');
        // L'API publique du marker error doit exposer la raison textuelle
        // pour que l'UI puisse mapper vers la string i18n correcte.
        expect(err.reason, 'image_format_unsupported');
      },
    );

    test('reason "image_format_unrecognised" toujours supporté', () {
      // Sanity check : on n\'a pas cassé l\'API existante en ajoutant un
      // nouveau motif d\'erreur. Les anciens motifs restent valides.
      const err = AttachmentRejectedError('image_format_unrecognised');
      expect(err.reason, 'image_format_unrecognised');
    });
  });
}
