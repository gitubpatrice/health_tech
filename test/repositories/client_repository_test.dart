import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/data/db/database.dart';
import 'package:health_tech/data/repositories/client_repository.dart';
import 'package:health_tech/data/vault/field_crypto.dart';
import 'package:health_tech/domain/address.dart';
import 'package:health_tech/domain/client.dart';
import 'package:health_tech/domain/consent.dart';

void main() {
  late HealthDb db;
  late FieldCrypto crypto;
  late ClientRepository repo;

  setUp(() {
    db = HealthDb.forTesting();
    crypto = FieldCrypto(Uint8List.fromList(List.generate(32, (i) => i)));
    repo = ClientRepository(db, crypto);
  });

  tearDown(() async {
    await db.close();
  });

  Client draftClient({String firstName = 'Alice', String lastName = 'Martin'}) {
    final now = DateTime.now();
    return Client(
      id: '',
      firstName: firstName,
      lastName: lastName,
      phone: '0612345678',
      email: 'alice@example.com',
      address: const Address(zipCode: '75001', city: 'Paris'),
      consents: ConsentSet(rgpdAt: now, disclaimerAt: now),
      healthNotes: 'Anxiété, sommeil léger',
      notes: 'Apporte sa propre couverture',
    );
  }

  test('create rejects clients without mandatory consents', () async {
    const draft = Client(id: '', firstName: 'X', lastName: 'Y');
    expect(() => repo.create(draft), throwsArgumentError);
  });

  test('create then getById returns decrypted sensitive fields', () async {
    final created = await repo.create(draftClient());
    expect(created.id, isNotEmpty);
    final fetched = await repo.getById(created.id);
    expect(fetched, isNotNull);
    expect(fetched!.firstName, 'Alice');
    expect(fetched.healthNotes, 'Anxiété, sommeil léger');
    expect(fetched.notes, 'Apporte sa propre couverture');
    expect(fetched.consents.hasMandatory, isTrue);
    expect(fetched.address.city, 'Paris');
  });

  test('watchAll filters by query', () async {
    await repo.create(draftClient(firstName: 'Alice', lastName: 'Martin'));
    await repo.create(draftClient(firstName: 'Bob', lastName: 'Durand'));

    final filtered = await repo.watchAll(query: 'Durand').first;
    expect(filtered.length, 1);
    expect(filtered.single.lastName, 'Durand');
  });

  test('softDelete hides from list but keeps row', () async {
    final c = await repo.create(draftClient());
    await repo.softDelete(c.id);
    final list = await repo.watchAll().first;
    expect(list, isEmpty);
    expect(await repo.getById(c.id), isNull);
  });

  test('purge removes the row physically', () async {
    final c = await repo.create(draftClient());
    await repo.purge(c.id);
    final list = await repo.watchAll().first;
    expect(list, isEmpty);
  });

  test('update preserves consent timestamps and rewrites encrypted fields',
      () async {
    final created = await repo.create(draftClient());
    final original = await repo.getById(created.id);
    final updated = await repo.update(
      original!.copyWith(healthNotes: 'Mise à jour santé'),
    );
    expect(updated.healthNotes, 'Mise à jour santé');
    expect(updated.consents.rgpdAt, original.consents.rgpdAt);
  });
}
