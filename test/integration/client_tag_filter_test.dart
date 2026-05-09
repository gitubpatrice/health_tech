import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/core/providers.dart';
import 'package:health_tech/data/db/database.dart';
import 'package:health_tech/data/repositories/client_repository.dart';
import 'package:health_tech/data/repositories/tag_repository.dart';
import 'package:health_tech/data/vault/field_crypto.dart';
import 'package:health_tech/domain/client.dart';
import 'package:health_tech/domain/consent.dart';
import 'package:health_tech/domain/tag.dart';
import 'package:health_tech/features/clients/client_providers.dart';

/// Integration test exercising the live composition between Drift streams,
/// repositories and Riverpod providers — without touching the UI.
///
/// We override the two repository providers directly (instead of the database
/// + vault providers) so the test does not need a real HealthVault instance.
void main() {
  test('clientsStreamProvider intersects free-text + tag filter', () async {
    final db = HealthDb.forTesting();
    addTearDown(db.close);
    final crypto = FieldCrypto(Uint8List.fromList(List.generate(32, (i) => i)));
    final clients = ClientRepository(db, crypto);
    final tags = TagRepository(db);

    final container = ProviderContainer(
      overrides: [
        clientRepositoryProvider.overrideWithValue(clients),
        tagRepositoryProvider.overrideWithValue(tags),
      ],
    );
    addTearDown(container.dispose);

    final now = DateTime.now();
    final consents = ConsentSet(rgpdAt: now, disclaimerAt: now);
    final c1 = await clients.create(
      Client(
        id: '',
        firstName: 'Alice',
        lastName: 'Martin',
        consents: consents,
      ),
    );
    final c2 = await clients.create(
      Client(id: '', firstName: 'Bob', lastName: 'Durand', consents: consents),
    );
    await clients.create(
      Client(
        id: '',
        firstName: 'Carole',
        lastName: 'Petit',
        consents: consents,
      ),
    );

    final stress = await tags.upsert(label: 'Stress');
    final sommeil = await tags.upsert(label: 'Sommeil');
    await tags.link(
      tagId: stress.id,
      ownerType: TagOwner.client,
      ownerId: c1.id,
    );
    await tags.link(
      tagId: sommeil.id,
      ownerType: TagOwner.client,
      ownerId: c1.id,
    );
    await tags.link(
      tagId: stress.id,
      ownerType: TagOwner.client,
      ownerId: c2.id,
    );

    // No filter → 3 clients.
    var list = await container.read(clientsStreamProvider.future);
    expect(list.length, 3);

    // Filter by Stress → 2 (c1, c2).
    container.read(clientsTagFilterProvider.notifier).state = {stress.id};
    list = await container.read(clientsStreamProvider.future);
    expect(list.map((c) => c.firstName).toSet(), {'Alice', 'Bob'});

    // Filter by Stress + Sommeil (AND) → 1 (c1 only).
    container.read(clientsTagFilterProvider.notifier).state = {
      stress.id,
      sommeil.id,
    };
    list = await container.read(clientsStreamProvider.future);
    expect(list.length, 1);
    expect(list.single.id, c1.id);

    // Free-text query stacks on top of the tag filter.
    container.read(clientsQueryProvider.notifier).state = 'Bob';
    container.read(clientsTagFilterProvider.notifier).state = {stress.id};
    list = await container.read(clientsStreamProvider.future);
    expect(list.length, 1);
    expect(list.single.firstName, 'Bob');
  });
}
