import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/core/errors.dart';
import 'package:health_tech/data/db/database.dart';
import 'package:health_tech/data/repositories/animal_repository.dart';
import 'package:health_tech/data/repositories/appointment_repository.dart';
import 'package:health_tech/data/repositories/attachment_repository.dart';
import 'package:health_tech/data/repositories/client_repository.dart';
import 'package:health_tech/data/repositories/session_repository.dart';
import 'package:health_tech/data/services/rgpd_export_service.dart';
import 'package:health_tech/data/vault/field_crypto.dart';
import 'package:health_tech/domain/animal.dart';
import 'package:health_tech/domain/client.dart';
import 'package:health_tech/domain/consent.dart';
import 'package:health_tech/domain/session.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  late HealthDb db;
  late FieldCrypto crypto;
  late RgpdExportService service;
  late ClientRepository clients;
  late AnimalRepository animals;
  late SessionRepository sessions;

  setUp(() {
    db = HealthDb.forTesting();
    crypto = FieldCrypto(Uint8List.fromList(List.generate(32, (i) => i)));
    clients = ClientRepository(db, crypto);
    animals = AnimalRepository(db, crypto);
    sessions = SessionRepository(db, crypto);
    service =
        RgpdExportService(
          clients: clients,
          animals: animals,
          sessions: sessions,
          appointments: AppointmentRepository(db, crypto),
          attachments: AttachmentRepository(db, crypto),
        )..overridePackageInfoLoader(
          () async => PackageInfo(
            appName: 'Health Tech',
            packageName: 'com.filestech.health_tech',
            version: '0.7.0',
            buildNumber: '1',
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'produces a valid ZIP with manifest, client, animals, sessions',
    () async {
      final now = DateTime.now();
      final c = await clients.create(
        Client(
          id: '',
          firstName: 'Alice',
          lastName: 'Martin',
          consents: ConsentSet(rgpdAt: now, disclaimerAt: now),
          healthNotes: 'Anxiété',
        ),
      );
      await animals.create(
        Animal(
          id: '',
          clientId: c.id,
          name: 'Rex',
          species: Species.dog,
          healthNotes: 'Boitement',
        ),
      );
      final s = Session(
        id: '',
        clientId: c.id,
        startAt: DateTime(2026, 5, 10, 14),
        endAt: DateTime(2026, 5, 10, 15),
        kind: SessionKind.human,
        report: const SessionReport(beforeState: 'Stress'),
        privateNote: 'PRIVATE-PRACTITIONER-NOTE',
      );
      await sessions.create(s);

      final zip = await service.exportClient(c.id);
      expect(zip.length, greaterThan(200));

      final archive = ZipDecoder().decodeBytes(zip);
      final names = archive.files.map((f) => f.name).toList();
      expect(names, contains('manifest.json'));
      expect(names, contains('client.json'));
      expect(names, contains('animals.json'));
      expect(names, contains('sessions.json'));

      // Sensitive content is in cleartext (decrypted) inside JSON.
      final sessionsJson =
          archive.files.firstWhere((f) => f.name == 'sessions.json').content
              as List<int>;
      final decoded = utf8.decode(sessionsJson);
      expect(decoded.contains('Stress'), isTrue);
      // The practitioner private note MUST NOT be exported.
      expect(decoded.contains('PRIVATE-PRACTITIONER-NOTE'), isFalse);

      final manifest =
          jsonDecode(
                utf8.decode(
                  archive.files
                          .firstWhere((f) => f.name == 'manifest.json')
                          .content
                      as List<int>,
                ),
              )
              as Map<String, dynamic>;
      expect(manifest['gdpr_article'], 15);
      expect(manifest['subject_client_id'], c.id);
      expect((manifest['counts'] as Map)['animals'], 1);
      expect((manifest['counts'] as Map)['sessions'], 1);
    },
  );

  test('throws when the client does not exist', () async {
    expect(
      () => service.exportClient('does-not-exist'),
      throwsA(isA<ValidationError>()),
    );
  });
}
