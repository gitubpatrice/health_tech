import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/data/services/session_pdf_exporter.dart';
import 'package:health_tech/domain/client.dart';
import 'package:health_tech/domain/consent.dart';
import 'package:health_tech/domain/session.dart';

void main() {
  group('SessionPdfExporter', () {
    test(
      'produces a non-empty PDF and never embeds the private note',
      () async {
        const exporter = SessionPdfExporter();
        final now = DateTime.now();
        final client = Client(
          id: 'c1',
          firstName: 'Alice',
          lastName: 'Martin',
          consents: ConsentSet(rgpdAt: now, disclaimerAt: now),
        );
        final session = Session(
          id: 's1',
          clientId: 'c1',
          startAt: DateTime(2026, 5, 10, 14, 0),
          endAt: DateTime(2026, 5, 10, 15, 0),
          kind: SessionKind.human,
          motives: const [SessionMotives.reiki],
          report: const SessionReport(
            beforeState: 'Stressée',
            observations: 'Énergie bloquée',
            afterState: 'Apaisement',
          ),
          privateNote: 'TOP-SECRET-PRACTITIONER-ONLY',
        );
        const strings = PdfStrings(
          title: 'Compte rendu',
          clientLine: 'Client',
          dateLine: 'Date',
          durationLine: 'Durée',
          motivesLine: 'Motifs',
          disclaimer: 'Pas un avis médical.',
          sectionReport: 'Compte rendu',
          before: 'Avant',
          client: 'Ressenti',
          observations: 'Observations',
          flow: 'Déroulé',
          zones: 'Zones',
          energetic: 'Énergétique',
          after: 'Après',
          advice: 'Conseils',
          next: 'Prochaine étape',
          motivesByKey: {SessionMotives.reiki: 'Reiki'},
        );
        final bytes = await exporter.render(
          session: session,
          client: client,
          s: strings,
        );
        expect(bytes.length, greaterThan(500));
        // Ensure the private note never appears in the rendered bytes.
        // PDF compresses text but we still scan a literal raw substring.
        final asString = String.fromCharCodes(bytes);
        expect(asString.contains('TOP-SECRET-PRACTITIONER-ONLY'), isFalse);
      },
    );
  });
}
