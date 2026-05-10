import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/data/db/database.dart';
import 'package:health_tech/data/repositories/animal_repository.dart';
import 'package:health_tech/data/repositories/client_repository.dart';
import 'package:health_tech/data/services/global_search_service.dart';
import 'package:health_tech/data/vault/field_crypto.dart';
import 'package:health_tech/domain/animal.dart';
import 'package:health_tech/domain/client.dart';
import 'package:health_tech/domain/consent.dart';

void main() {
  late HealthDb db;
  late FieldCrypto crypto;
  late ClientRepository clients;
  late AnimalRepository animals;
  late GlobalSearchService search;

  setUp(() async {
    db = HealthDb.forTesting();
    crypto = FieldCrypto(Uint8List.fromList(List.generate(32, (i) => i)));
    clients = ClientRepository(db, crypto);
    animals = AnimalRepository(db, crypto);
    search = GlobalSearchService(db);

    final now = DateTime.now();
    Future<Client> mkClient(
      String first,
      String last, {
      String? profession,
      String? email,
    }) => clients.create(
      Client(
        id: '',
        kind: ClientKind.individual,
        lastName: last,
        firstName: first,
        profession: profession,
        email: email,
        consents: ConsentSet(rgpdAt: now, disclaimerAt: now),
      ),
    );
    final jean = await mkClient(
      'Jean',
      'Dupont',
      profession: 'Géobiologue',
      email: 'jean@example.com',
    );
    await mkClient('Marie', 'Martin', profession: 'Reiki');
    await mkClient('Paul', 'Dupont', profession: 'Reiki');
    // Pour tester l'AND multi-tokens : "Jean Dupont" doit matcher seul Jean.

    await animals.create(
      Animal(
        id: '',
        clientId: jean.id,
        name: 'Rex',
        species: 'dog',
        breed: 'Labrador',
        color: 'noir',
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('matche un client par prénom', () async {
    final hits = await search.search('Jean');
    final clientHits = hits
        .where((h) => h.kind == SearchHitKind.client)
        .toList();
    expect(clientHits.length, 1);
    expect(clientHits.single.title, 'Jean Dupont');
  });

  test('matche un client par profession', () async {
    final hits = await search.search('Reiki');
    final clientHits = hits
        .where((h) => h.kind == SearchHitKind.client)
        .toList();
    expect(clientHits.length, 2);
  });

  test('AND multi-tokens : "Jean Dupont" matche seul Jean', () async {
    // 2 clients ont "Dupont" en lastName mais 1 seul a "Jean" en firstName.
    final hits = await search.search('Jean Dupont');
    final clientHits = hits
        .where((h) => h.kind == SearchHitKind.client)
        .toList();
    expect(clientHits.length, 1);
    expect(clientHits.single.title, 'Jean Dupont');
  });

  test('AND multi-tokens : "Marie Dupont" ne matche personne', () async {
    final hits = await search.search('Marie Dupont');
    expect(hits.where((h) => h.kind == SearchHitKind.client), isEmpty);
  });

  test('strip wildcards SQL : "%" seul ne matche rien', () async {
    final hits = await search.search('%');
    expect(hits, isEmpty, reason: 'le strip doit produire une query vide');
  });

  test('strip wildcards SQL : "%_" est vide après strip', () async {
    final hits = await search.search('%_');
    expect(hits, isEmpty);
  });

  test(
    'strip wildcards SQL : "Jean%" matche "Jean" (le % est strippé)',
    () async {
      final hits = await search.search('Jean%');
      final clientHits = hits
          .where((h) => h.kind == SearchHitKind.client)
          .toList();
      expect(clientHits.length, 1);
      expect(clientHits.single.title, 'Jean Dupont');
    },
  );

  test('matche un animal par espèce', () async {
    final hits = await search.search('dog');
    final animalHits = hits
        .where((h) => h.kind == SearchHitKind.animal)
        .toList();
    expect(animalHits.length, 1);
    expect(animalHits.single.title, 'Rex');
  });

  test('matche un animal par nom', () async {
    final hits = await search.search('Rex');
    expect(hits.any((h) => h.kind == SearchHitKind.animal), isTrue);
  });

  test('query vide retourne []', () async {
    expect(await search.search(''), isEmpty);
    expect(await search.search('   '), isEmpty);
  });
}
