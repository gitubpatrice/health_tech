import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/core/errors.dart';
import 'package:health_tech/data/db/database.dart';
import 'package:health_tech/data/repositories/client_repository.dart';
import 'package:health_tech/data/repositories/session_repository.dart';
import 'package:health_tech/data/vault/field_crypto.dart';
import 'package:health_tech/domain/client.dart';
import 'package:health_tech/domain/consent.dart';
import 'package:health_tech/domain/session.dart';

void main() {
  late HealthDb db;
  late FieldCrypto crypto;
  late SessionRepository repo;
  late String clientId;

  setUp(() async {
    db = HealthDb.forTesting();
    crypto = FieldCrypto(Uint8List.fromList(List.generate(32, (i) => i)));
    repo = SessionRepository(db, crypto);
    final now = DateTime.now();
    final c = await ClientRepository(db, crypto).create(
      Client(
        id: '',
        firstName: 'Test',
        lastName: 'Client',
        consents: ConsentSet(rgpdAt: now, disclaimerAt: now),
      ),
    );
    clientId = c.id;
  });

  tearDown(() async {
    await db.close();
  });

  Session draft({Duration offset = Duration.zero}) {
    final start = DateTime(2026, 5, 10, 14, 0).add(offset);
    return Session(
      id: '',
      clientId: clientId,
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      kind: SessionKind.human,
      motives: const [SessionMotives.reiki, SessionMotives.stress],
      report: const SessionReport(
        beforeState: 'Stressée',
        observations: 'Énergie bloquée plexus',
        afterState: 'Détente',
      ),
      privateNote: 'À surveiller au prochain RDV',
    );
  }

  test('rejects sessions where end <= start', () async {
    final start = DateTime.now();
    final invalid = Session(
      id: '',
      clientId: clientId,
      startAt: start,
      endAt: start,
      kind: SessionKind.human,
    );
    expect(() => repo.create(invalid), throwsA(isA<ValidationError>()));
  });

  test('round-trip preserves report sections and motives', () async {
    final created = await repo.create(draft());
    final fetched = await repo.getById(created.id);
    expect(fetched, isNotNull);
    expect(fetched!.report.beforeState, 'Stressée');
    expect(fetched.report.observations, 'Énergie bloquée plexus');
    expect(fetched.privateNote, 'À surveiller au prochain RDV');
    expect(
      fetched.motives,
      containsAll([SessionMotives.reiki, SessionMotives.stress]),
    );
  });

  test('watchByClient orders by start desc', () async {
    await repo.create(draft(offset: const Duration(days: -7)));
    await repo.create(draft());
    final list = await repo.watchByClient(clientId).first;
    expect(list.length, 2);
    expect(list.first.startAt.isAfter(list.last.startAt), isTrue);
  });

  test('watchInRange filters correctly', () async {
    await repo.create(draft(offset: const Duration(days: -100)));
    await repo.create(draft());
    final list = await repo
        .watchInRange(DateTime(2026, 5, 1), DateTime(2026, 5, 31))
        .first;
    expect(list.length, 1);
  });
}
