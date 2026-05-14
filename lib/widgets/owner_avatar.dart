import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../domain/attachment.dart';
import '../features/attachments/attachment_viewer.dart';

/// Avatar circulaire pour un client ou un animal — lit l'avatar courant
/// (`ownerAvatarProvider`) et affiche, par ordre de priorité :
///
/// 1. la photo déchiffrée (`MemoryImage`) — si un avatar est défini ;
/// 2. le `fallbackChild` (initiales pour un client, icône d'espèce pour un
///    animal) — sinon.
///
/// Le widget est volontairement **lecture seule** : pas de bouton, pas de
/// sheet d'édition. C'est `AvatarPicker` qui assume cette responsabilité
/// dans le formulaire / la fiche.
///
/// **Perf** : le `Image.memory` est plafonné à `cacheSize × dpr` pour
/// éviter de matérialiser un bitmap full-resolution (12 MP ≈ 48 Mo RGBA).
/// Pour une vignette de liste 40 dp, ça représente ~80 Ko décodés au lieu
/// de plusieurs Mo. Le cache image Flutter est par ailleurs clear au lock
/// (`VaultSessionController.lock` → `PaintingBinding.imageCache.clear`).
///
/// **Sécurité** : aucun contenu en clair n'atteint le disque ; les bytes
/// déchiffrés ne quittent jamais la RAM ; au lock, le cache image est wipé.
/// Aucun chemin de fichier `.enc` n'est exposé à l'UI.
class OwnerAvatar extends ConsumerWidget {
  const OwnerAvatar({
    super.key,
    required this.ownerType,
    required this.ownerId,
    required this.fallbackChild,
    this.radius = 22,
    this.tappableForView = false,
  });

  final String ownerType;
  final String ownerId;

  /// Widget affiché lorsque le couple `(ownerType, ownerId)` n'a pas
  /// d'avatar. Conserve la cohérence avec les patterns historiques :
  /// initiales pour le client, icône d'espèce pour l'animal.
  final Widget fallbackChild;

  final double radius;

  /// Quand `true`, un tap ouvre `AttachmentViewer` plein écran sur la
  /// photo (zoom + pan). Utile dans les fiches détail. La liste reste
  /// non-tappable pour ne pas voler le tap au `ListTile.onTap`.
  final bool tappableForView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAvatar = ref.watch(
      ownerAvatarProvider((ownerType: ownerType, ownerId: ownerId)),
    );
    final scheme = Theme.of(context).colorScheme;
    return asyncAvatar.when(
      // Pendant le 1er frame du stream Drift on garde le fallback :
      // évite un flash gris (CircularProgressIndicator dans une vignette
      // 40 dp est visuellement bruyant, et pour 99% des fiches il n'y a
      // rien à charger).
      loading: () => _circle(scheme, fallbackChild),
      // En cas d'erreur (DB locked en transition, etc.) on dégrade
      // proprement — pas de message rouge dans une tile.
      error: (_, _) => _circle(scheme, fallbackChild),
      data: (att) {
        if (att == null) return _circle(scheme, fallbackChild);
        return _AvatarImage(
          attachment: att,
          radius: radius,
          fallbackChild: fallbackChild,
          tappableForView: tappableForView,
        );
      },
    );
  }

  Widget _circle(ColorScheme scheme, Widget child) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.surfaceContainerHigh,
      foregroundColor: scheme.onSurfaceVariant,
      child: child,
    );
  }
}

class _AvatarImage extends ConsumerWidget {
  const _AvatarImage({
    required this.attachment,
    required this.radius,
    required this.fallbackChild,
    required this.tappableForView,
  });

  final Attachment attachment;
  final double radius;
  final Widget fallbackChild;
  final bool tappableForView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Cap du décodage : `radius * 2 * dpr * 2` = diamètre × dpr × marge zoom
    // — assez pour rester net même si l'utilisateur zoome temporairement
    // via Material's animations, mais loin du bitmap full-resolution.
    final cacheSize = (radius * 2 * dpr * 2).round();
    final asyncBytes = ref.watch(attachmentBytesProvider(attachment.id));
    return asyncBytes.when(
      loading: () => CircleAvatar(
        radius: radius,
        backgroundColor: scheme.surfaceContainerHigh,
        child: SizedBox(
          width: radius,
          height: radius,
          child: const CircularProgressIndicator(strokeWidth: 1.5),
        ),
      ),
      error: (_, _) => CircleAvatar(
        radius: radius,
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurfaceVariant,
        child: fallbackChild,
      ),
      data: (bytes) {
        final image = MemoryImage(bytes);
        final circle = CircleAvatar(
          radius: radius,
          backgroundColor: scheme.surfaceContainerHigh,
          foregroundImage: ResizeImage(
            image,
            width: cacheSize,
            // policy=fit garde le ratio sans forcer 1:1, le crop circulaire
            // est appliqué par le `CircleAvatar`.
            policy: ResizeImagePolicy.fit,
          ),
          child: fallbackChild,
        );
        if (!tappableForView) return circle;
        return _ViewableAvatar(attachment: attachment, child: circle);
      },
    );
  }
}

/// Décor tappable qui ouvre `AttachmentViewer` plein écran (zoom + pan).
/// Le viewer ré-utilise `attachmentBytesProvider` côté Riverpod, donc la
/// transition ne paie pas un second decrypt — la valeur est servie depuis
/// le cache provider tant qu'elle n'a pas été disposée.
class _ViewableAvatar extends StatelessWidget {
  const _ViewableAvatar({required this.attachment, required this.child});

  final Attachment attachment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => AttachmentViewer(attachment: attachment),
          ),
        );
      },
      child: child,
    );
  }
}
