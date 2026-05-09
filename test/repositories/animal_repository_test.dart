import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/data/db/database.dart';
import 'package:health_tech/data/repositories/animal_repository.dart';
import 'package:health_tech/data/repositories/client_repository.dart';
import 'package:health_tech/data/vault/field_crypto.dart';
import 'package:health_tech/domain/animal.dart';
import 'package:health_tech/domain/client.dart';
import 'package:health_tech/domain/consent.dart';

void main() {
  late HealthDb db;
  late FieldCrypto crypto;
  late AnimalRepository repo;
  late ClientRepository clients;
  late String clientId;

  setUp(() async {
    db = HealthDb.forTesting();
    crypto = FieldCrypto(Uint8List.fromList(List.generate(32, (i) => i)));
    repo = AnimalRepository(db, crypto);
    clients = ClientRepository(db, crypto);
    final now = DateTime.now();
    final client = await clients.create(Client(
      id: '',
      firstName: 'Owner',
      lastName: 'Test',
      consents: ConsentSet(rgpdAt: now, disclaimerAt: now),
    ));
    clientId = client.id;
  });

  tearDown(() async {
    await db.close();
  });

  Animal draft({String name = 'Rex', String species = Species.dog}) => Animal(
        id: '',
        clientId: clientId,
        name: name,
        species: species,
        weightGrams: 12000,
        healthNotes: 'Léger boitement antérieur droit',
        behaviorNotes: 'Anxieux en début de séance',
      );

  test('create + getById decrypts notes', () async {
    final created = await repo.create(draft());
    final fetched = await repo.getById(created.id);
    expect(fetched, isNotNull);
    expect(fetched!.name, 'Rex');
    expect(fetched.healthNotes, 'Léger boitement antérieur droit');
    expect(fetched.behaviorNotes, 'Anxieux en début de séance');
    expect(fetched.weightKg, 12.0);
  });

  test('watchByClient streams only this client animals', () async {
    await repo.create(draft(name: 'Rex'));
    await repo.create(draft(name: 'Mia', species: Species.cat));
    final list = await repo.watchByClient(clientId).first;
    expect(list.map((a) => a.name).toSet(), {'Rex', 'Mia'});
  });

  test('species filter narrows the global list', () async {
    await repo.create(draft(name: 'Rex'));
    await repo.create(draft(name: 'Mia', species: Species.cat));
    final cats = await repo
        .watchAll(speciesFilter: Species.cat)
        .first;
    expect(cats.length, 1);
    expect(cats.single.name, 'Mia');
  });

  test('softDelete hides from list', () async {
    final a = await repo.create(draft());
    await repo.softDelete(a.id);
    final list = await repo.watchAll().first;
    expect(list, isEmpty);
  });
}
