import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/data/db/database.dart';
import 'package:health_tech/data/repositories/tag_repository.dart';
import 'package:health_tech/domain/tag.dart';

void main() {
  late HealthDb db;
  late TagRepository repo;

  setUp(() {
    db = HealthDb.forTesting();
    repo = TagRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('upsert creates a tag and is idempotent on label match', () async {
    final a = await repo.upsert(label: 'Stress');
    final b = await repo.upsert(label: 'stress');
    expect(a.id, b.id);
  });

  test('rejects empty labels', () async {
    expect(() => repo.upsert(label: '   '), throwsArgumentError);
  });

  test('link / unlink toggles ownership', () async {
    final t = await repo.upsert(label: 'Suivi régulier');
    await repo.link(
      tagId: t.id,
      ownerType: TagOwner.client,
      ownerId: 'c1',
    );
    var attached = await repo
        .watchForOwner(ownerType: TagOwner.client, ownerId: 'c1')
        .first;
    expect(attached.length, 1);
    await repo.unlink(
      tagId: t.id,
      ownerType: TagOwner.client,
      ownerId: 'c1',
    );
    attached = await repo
        .watchForOwner(ownerType: TagOwner.client, ownerId: 'c1')
        .first;
    expect(attached, isEmpty);
  });

  test('ownerIdsTaggedWithAll requires every tag', () async {
    final t1 = await repo.upsert(label: 'tag1');
    final t2 = await repo.upsert(label: 'tag2');
    await repo.link(tagId: t1.id, ownerType: TagOwner.client, ownerId: 'c1');
    await repo.link(tagId: t2.id, ownerType: TagOwner.client, ownerId: 'c1');
    await repo.link(tagId: t1.id, ownerType: TagOwner.client, ownerId: 'c2');

    final both = await repo.ownerIdsTaggedWithAll(
      ownerType: TagOwner.client,
      tagIds: [t1.id, t2.id],
    );
    expect(both, equals({'c1'}));

    final justOne = await repo.ownerIdsTaggedWithAll(
      ownerType: TagOwner.client,
      tagIds: [t1.id],
    );
    expect(justOne, equals({'c1', 'c2'}));

    final emptyFilter = await repo.ownerIdsTaggedWithAll(
      ownerType: TagOwner.client,
      tagIds: [],
    );
    expect(emptyFilter, isNull);
  });
}
