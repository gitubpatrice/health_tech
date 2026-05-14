import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/core/errors.dart';
import 'package:health_tech/data/db/database.dart';
import 'package:health_tech/data/repositories/attachment_repository.dart';
import 'package:health_tech/data/vault/field_crypto.dart';
import 'package:health_tech/domain/attachment.dart';
import 'package:path/path.dart' as p;
// `PathProviderPlatform.instance` est l'API officielle d'override des
// plugins federated v2.x : le mock par `MethodChannel` brut est obsolète
// depuis le `PlatformInterface` v2.
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Tests `AttachmentRepository.setAvatar` / `getAvatar` / `watchAvatar` /
/// `clearAvatar` + l'invariant « au plus un avatar par owner » + le
/// filtrage `excludeKinds: {avatar}` du `watchByOwner` standard.
///
/// Le repo écrit physiquement des fichiers `.enc` sous
/// `<appSupport>/attachments/`. Pour ne pas dépendre du device on
/// substitue `PathProviderPlatform.instance` par une implémentation de
/// test qui pointe vers un `Directory.systemTemp.createTemp()` jetable
/// au tearDown — c'est l'API officielle des plugins federated v2.x
/// (le mock par `MethodChannel` brut ne marche plus depuis le passage
/// au `PlatformInterface` v2).
class _TmpPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TmpPathProvider(this.support);
  final String support;
  @override
  Future<String?> getApplicationSupportPath() async => support;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HealthDb db;
  late FieldCrypto crypto;
  late AttachmentRepository repo;
  late Directory tmpRoot;
  late PathProviderPlatform previousPathProvider;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('avatar_test_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TmpPathProvider(tmpRoot.path);

    db = HealthDb.forTesting();
    crypto = FieldCrypto(Uint8List.fromList(List.generate(32, (i) => i)));
    repo = AttachmentRepository(db, crypto);
  });

  tearDown(() async {
    await db.close();
    PathProviderPlatform.instance = previousPathProvider;
    if (tmpRoot.existsSync()) {
      await tmpRoot.delete(recursive: true);
    }
  });

  // PNG minimal valide pour `ImageBoundsProbe.probe` — signature 8 octets
  // + chunk IHDR avec largeur/hauteur 2×2. Volontairement < 300 KB pour
  // que `ImageCompress.maybeCompress` skip l'étape de compression isolate
  // (sinon le test exigerait le runtime `image` complet — pas le sujet).
  Uint8List minimalPng() => Uint8List.fromList(<int>[
    // Signature PNG
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    // IHDR chunk : length=13
    0x00, 0x00, 0x00, 0x0D,
    // Type = "IHDR"
    0x49, 0x48, 0x44, 0x52,
    // Width = 2
    0x00, 0x00, 0x00, 0x02,
    // Height = 2
    0x00, 0x00, 0x00, 0x02,
    // bit depth + color type + compression + filter + interlace
    0x08, 0x06, 0x00, 0x00, 0x00,
    // CRC dummy (non vérifié par notre probe)
    0x00, 0x00, 0x00, 0x00,
  ]);

  group('AttachmentRepository.setAvatar', () {
    test('crée un avatar quand aucun n\'existe encore', () async {
      final att = await repo.setAvatar(
        ownerType: AttachmentOwner.client,
        ownerId: 'c-1',
        bytes: minimalPng(),
        mimeType: 'image/png',
        filename: 'avatar.png',
      );
      expect(att.kind, AttachmentKind.avatar);
      expect(att.ownerType, AttachmentOwner.client);
      expect(att.ownerId, 'c-1');

      final fetched = await repo.getAvatar(
        ownerType: AttachmentOwner.client,
        ownerId: 'c-1',
      );
      expect(fetched, isNotNull);
      expect(fetched!.id, att.id);
      // Le fichier `.enc` a effectivement été écrit sur disque sous le
      // tmp dir mocké.
      final encPath = p.join(tmpRoot.path, 'attachments', att.storagePath);
      expect(File(encPath).existsSync(), true);
    });

    test(
      'remplace l\'avatar existant (invariant : 1 seul par owner)',
      () async {
        final first = await repo.setAvatar(
          ownerType: AttachmentOwner.client,
          ownerId: 'c-1',
          bytes: minimalPng(),
          mimeType: 'image/png',
          filename: 'old.png',
        );
        final firstFile = File(
          p.join(tmpRoot.path, 'attachments', first.storagePath),
        );
        expect(firstFile.existsSync(), true);

        final second = await repo.setAvatar(
          ownerType: AttachmentOwner.client,
          ownerId: 'c-1',
          bytes: minimalPng(),
          mimeType: 'image/png',
          filename: 'new.png',
        );
        expect(second.id, isNot(first.id));

        // L'ancien fichier `.enc` doit avoir été purgé physiquement,
        // pas seulement la row DB.
        expect(firstFile.existsSync(), false);
        // Et il ne doit rester qu'UN avatar `deletedAt IS NULL` pour l'owner.
        final remaining = await repo.getAvatar(
          ownerType: AttachmentOwner.client,
          ownerId: 'c-1',
        );
        expect(remaining, isNotNull);
        expect(remaining!.id, second.id);
      },
    );

    test('isole les avatars par owner', () async {
      await repo.setAvatar(
        ownerType: AttachmentOwner.client,
        ownerId: 'c-1',
        bytes: minimalPng(),
        mimeType: 'image/png',
        filename: 'c1.png',
      );
      await repo.setAvatar(
        ownerType: AttachmentOwner.client,
        ownerId: 'c-2',
        bytes: minimalPng(),
        mimeType: 'image/png',
        filename: 'c2.png',
      );
      // Animal avec le même `ownerId` que c-1 ne partage pas l'avatar :
      // la séparation se fait sur le couple `(ownerType, ownerId)`.
      await repo.setAvatar(
        ownerType: AttachmentOwner.animal,
        ownerId: 'c-1',
        bytes: minimalPng(),
        mimeType: 'image/png',
        filename: 'a.png',
      );
      final clientAvatar = await repo.getAvatar(
        ownerType: AttachmentOwner.client,
        ownerId: 'c-1',
      );
      final animalAvatar = await repo.getAvatar(
        ownerType: AttachmentOwner.animal,
        ownerId: 'c-1',
      );
      expect(clientAvatar, isNotNull);
      expect(animalAvatar, isNotNull);
      expect(clientAvatar!.id, isNot(animalAvatar!.id));
    });

    test('readBytes restitue le PNG identique au byte près', () async {
      final src = minimalPng();
      final att = await repo.setAvatar(
        ownerType: AttachmentOwner.client,
        ownerId: 'c-1',
        bytes: src,
        mimeType: 'image/png',
        filename: 'avatar.png',
      );
      final read = await repo.readBytes(att.id);
      expect(read, equals(src));
    });
  });

  group('AttachmentRepository.getAvatar', () {
    test('renvoie null s\'il n\'y a aucun avatar', () async {
      final res = await repo.getAvatar(
        ownerType: AttachmentOwner.client,
        ownerId: 'c-1',
      );
      expect(res, isNull);
    });
  });

  group('AttachmentRepository.setAvatar — garde-fou mime', () {
    // Sans cette garde, un appelant qui passerait par erreur un mime
    // non-image se verrait stocker l'avatar SANS déclencher
    // `ImageBoundsProbe` (qui n'agit que sur `image/*` côté importBytes)
    // — donc sans rejet d'image-bombe et sans compression. On vérifie
    // que `setAvatar` refuse en amont avec `AttachmentRejectedError`.
    test('refuse un mime non-image (PDF / OCTET-STREAM)', () async {
      await expectLater(
        repo.setAvatar(
          ownerType: AttachmentOwner.client,
          ownerId: 'c-1',
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
          mimeType: 'application/pdf',
          filename: 'forged.pdf',
        ),
        throwsA(
          isA<AttachmentRejectedError>().having(
            (e) => e.reason,
            'reason',
            'image_format_unrecognised',
          ),
        ),
      );
      // Et l'invariant : aucune row avatar n'a été écrite.
      expect(
        await repo.getAvatar(ownerType: AttachmentOwner.client, ownerId: 'c-1'),
        isNull,
      );
    });
  });

  group('AttachmentRepository.watchAvatar', () {
    test('émet null puis l\'avatar puis null après clear', () async {
      final stream = repo.watchAvatar(
        ownerType: AttachmentOwner.client,
        ownerId: 'c-1',
      );
      final emitted = <Attachment?>[];
      final sub = stream.listen(emitted.add);
      // 1) état initial
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // 2) après set
      await repo.setAvatar(
        ownerType: AttachmentOwner.client,
        ownerId: 'c-1',
        bytes: minimalPng(),
        mimeType: 'image/png',
        filename: 'a.png',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // 3) après clear
      await repo.clearAvatar(ownerType: AttachmentOwner.client, ownerId: 'c-1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      // On a au moins observé : null → Attachment → null.
      expect(emitted.first, isNull);
      expect(emitted.any((e) => e != null), true);
      expect(emitted.last, isNull);
    });
  });

  group('AttachmentRepository.clearAvatar', () {
    test('no-op s\'il n\'y a pas d\'avatar', () async {
      // Doit simplement ne rien faire (pas throw).
      await repo.clearAvatar(ownerType: AttachmentOwner.client, ownerId: 'c-1');
      expect(
        await repo.getAvatar(ownerType: AttachmentOwner.client, ownerId: 'c-1'),
        isNull,
      );
    });

    test('purge la row + le fichier `.enc`', () async {
      final att = await repo.setAvatar(
        ownerType: AttachmentOwner.client,
        ownerId: 'c-1',
        bytes: minimalPng(),
        mimeType: 'image/png',
        filename: 'a.png',
      );
      final f = File(p.join(tmpRoot.path, 'attachments', att.storagePath));
      expect(f.existsSync(), true);
      await repo.clearAvatar(ownerType: AttachmentOwner.client, ownerId: 'c-1');
      expect(
        await repo.getAvatar(ownerType: AttachmentOwner.client, ownerId: 'c-1'),
        isNull,
      );
      expect(f.existsSync(), false);
    });
  });

  group('AttachmentRepository.watchByOwner', () {
    test(
      'exclut l\'avatar par défaut (separation d\'écran AttachmentsSection)',
      () async {
        // 1 avatar + 1 attachment "document" sur le même owner.
        await repo.setAvatar(
          ownerType: AttachmentOwner.client,
          ownerId: 'c-1',
          bytes: minimalPng(),
          mimeType: 'image/png',
          filename: 'avatar.png',
        );
        await repo.importBytes(
          ownerType: AttachmentOwner.client,
          ownerId: 'c-1',
          kind: AttachmentKind.document,
          bytes: Uint8List.fromList([1, 2, 3, 4]),
          mimeType: 'application/octet-stream',
          filename: 'doc.bin',
        );

        // Default exclude = {avatar} → seul le document apparaît.
        final visible = await repo
            .watchByOwner(ownerType: AttachmentOwner.client, ownerId: 'c-1')
            .first;
        expect(visible, hasLength(1));
        expect(visible.single.kind, AttachmentKind.document);

        // En passant `excludeKinds: const {}`, on récupère tout (cas
        // utilisé par `RgpdExportService` pour l'article 15).
        final all = await repo
            .watchByOwner(
              ownerType: AttachmentOwner.client,
              ownerId: 'c-1',
              excludeKinds: const {},
            )
            .first;
        expect(all, hasLength(2));
        final kinds = all.map((a) => a.kind).toSet();
        expect(
          kinds,
          containsAll([AttachmentKind.avatar, AttachmentKind.document]),
        );
      },
    );
  });

  group('AttachmentRepository.purgeAllForOwner', () {
    test(
      'cascade aussi l\'avatar (suppression compte client / animal)',
      () async {
        final av = await repo.setAvatar(
          ownerType: AttachmentOwner.client,
          ownerId: 'c-1',
          bytes: minimalPng(),
          mimeType: 'image/png',
          filename: 'avatar.png',
        );
        final doc = await repo.importBytes(
          ownerType: AttachmentOwner.client,
          ownerId: 'c-1',
          kind: AttachmentKind.document,
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'application/octet-stream',
          filename: 'doc.bin',
        );
        final avFile = File(
          p.join(tmpRoot.path, 'attachments', av.storagePath),
        );
        final docFile = File(
          p.join(tmpRoot.path, 'attachments', doc.storagePath),
        );
        expect(avFile.existsSync(), true);
        expect(docFile.existsSync(), true);

        final removed = await repo.purgeAllForOwner(
          ownerType: AttachmentOwner.client,
          ownerId: 'c-1',
        );
        expect(removed, 2);
        expect(avFile.existsSync(), false);
        expect(docFile.existsSync(), false);
        expect(
          await repo.getAvatar(
            ownerType: AttachmentOwner.client,
            ownerId: 'c-1',
          ),
          isNull,
        );
      },
    );
  });
}
