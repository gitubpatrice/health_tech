import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/errors.dart';
import '../core/providers.dart';
import '../l10n/generated/app_localizations.dart';
import 'snack_utils.dart';

/// Sélecteur de photo-avatar pour une fiche client / animal.
///
/// Deux modes de fonctionnement :
///
/// - **immédiat** (`controller == null`) : on suppose que `ownerId` désigne
///   une entité déjà persistée. Toute action (capture, choix galerie,
///   suppression) écrit immédiatement via `AttachmentRepository.setAvatar`
///   ou `clearAvatar`, puis `ownerAvatarProvider` re-stream l'avatar.
///
/// - **différé** (`controller != null`) : utilisé en CRÉATION d'entité
///   (`ownerId` pas encore connu). Les bytes / mime / filename sont
///   stockés dans le contrôleur ; le formulaire appelle ensuite
///   `controller.commit(...)` après le `repo.create(draft)` pour effectuer
///   l'écriture une fois qu'un `ownerId` existe.
///
/// **Sécurité** : aucune écriture transitoire en clair sur le disque
/// app-managed ; les bytes ne quittent la RAM que sous forme chiffrée
/// AES-GCM dans `<appSupport>/attachments/<uuid>.enc`. Les caches
/// `image_picker` (`<temp>/image_picker/`) ne contiennent que des
/// originaux temporaires que l'OS purge à terme ; on en force la
/// disparition après chaque succès via `_purgeImagePickerCache`. Le mode
/// `requestFullMetadata: false` strip EXIF/GPS dès la lecture par
/// image_picker.
class AvatarPicker extends ConsumerStatefulWidget {
  const AvatarPicker({
    super.key,
    required this.ownerType,
    required this.ownerId,
    required this.placeholder,
    this.controller,
    this.radius = 48,
  });

  /// `AttachmentOwner.client` ou `AttachmentOwner.animal`.
  final String ownerType;

  /// Vide en mode différé (création) ; renseigné en mode immédiat (édition).
  final String ownerId;

  /// Affiché quand aucune photo n'existe (ex : `Icon(Icons.person_outline)`,
  /// `Icon(Icons.pets_outlined)`).
  final Widget placeholder;

  /// Si fourni, active le mode différé : les actions ne touchent pas au repo
  /// directement, elles modifient le contrôleur. Le formulaire est ensuite
  /// responsable d'appeler `controller.commit(ref, ownerType, ownerId)`
  /// après save.
  final AvatarPickerController? controller;

  final double radius;

  @override
  ConsumerState<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends ConsumerState<AvatarPicker> {
  /// `true` pendant la prise de photo / le choix galerie / le pipeline
  /// (compression isolate + chiffrement AES-GCM + écriture). Bloque les
  /// taps successifs et affiche un overlay progress.
  bool _busy = false;

  bool get _isDeferred => widget.controller != null;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AvatarPicker old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._detach();
      widget.controller?._attach(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final size = widget.radius * 2;
    return Semantics(
      label: l10n.avatarSemanticLabel,
      button: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _busy ? null : _openSheet,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: _buildPreview(scheme),
            ),
            // Pictogramme camera en bas-droite : signal visuel "ce cercle
            // est éditable" sans avoir besoin d'expliquer "tap n'importe
            // où sur la photo".
            Positioned(
              right: 0,
              bottom: 0,
              child: Material(
                shape: const CircleBorder(),
                color: scheme.primary,
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.photo_camera_outlined,
                    size: 16,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ),
            if (_busy)
              SizedBox(
                width: size,
                height: size,
                child: ClipOval(
                  child: ColoredBox(
                    color: scheme.scrim.withValues(alpha: 0.4),
                    child: const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ColorScheme scheme) {
    final ctrl = widget.controller;
    // Mode différé : si le controller a des bytes en attente, on les affiche
    // directement (pas encore en DB).
    if (_isDeferred && ctrl != null && ctrl.pendingBytes != null) {
      return _CircleImage(
        bytes: ctrl.pendingBytes!,
        radius: widget.radius,
        scheme: scheme,
      );
    }
    if (_isDeferred && ctrl != null && ctrl.removeRequested) {
      // L'utilisateur a explicitement demandé la suppression : on n'affiche
      // pas la photo DB éventuellement déjà présente, pour ne pas mentir
      // entre l'instant de l'action et le commit du save.
      return _placeholderCircle(scheme);
    }
    // Mode immédiat (ou différé sans pending) : on reflète l'état DB.
    if (widget.ownerId.isEmpty) {
      return _placeholderCircle(scheme);
    }
    final asyncAvatar = ref.watch(
      ownerAvatarProvider((
        ownerType: widget.ownerType,
        ownerId: widget.ownerId,
      )),
    );
    return asyncAvatar.when(
      loading: () => _placeholderCircle(scheme),
      error: (_, _) => _placeholderCircle(scheme),
      data: (att) {
        if (att == null) return _placeholderCircle(scheme);
        return _AvatarImageFromProvider(
          attachmentId: att.id,
          radius: widget.radius,
          fallback: _placeholderCircle(scheme),
        );
      },
    );
  }

  Widget _placeholderCircle(ColorScheme scheme) {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: scheme.surfaceContainerHigh,
      foregroundColor: scheme.onSurfaceVariant,
      child: IconTheme(
        data: IconThemeData(
          size: widget.radius,
          color: scheme.onSurfaceVariant,
        ),
        child: widget.placeholder,
      ),
    );
  }

  Future<void> _openSheet() async {
    final l10n = AppL10n.of(context);
    final hasAvatar = await _hasAvatar();
    if (!mounted) return;
    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.avatarTakePhoto),
              onTap: () => Navigator.of(ctx).pop(_AvatarAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.avatarChooseFromGallery),
              onTap: () => Navigator.of(ctx).pop(_AvatarAction.gallery),
            ),
            if (hasAvatar)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: Text(l10n.avatarRemove),
                onTap: () => Navigator.of(ctx).pop(_AvatarAction.remove),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _AvatarAction.camera:
        await _pickFrom(ImageSource.camera);
      case _AvatarAction.gallery:
        await _pickFrom(ImageSource.gallery);
      case _AvatarAction.remove:
        await _confirmAndRemove();
    }
  }

  Future<bool> _hasAvatar() async {
    final ctrl = widget.controller;
    if (_isDeferred && ctrl != null) {
      if (ctrl.pendingBytes != null) return true;
      if (ctrl.removeRequested) return false;
    }
    if (widget.ownerId.isEmpty) return false;
    final repo = ref.read(attachmentRepositoryProvider);
    final att = await repo.getAvatar(
      ownerType: widget.ownerType,
      ownerId: widget.ownerId,
    );
    return att != null;
  }

  Future<void> _pickFrom(ImageSource source) async {
    final l10n = AppL10n.of(context);
    setState(() => _busy = true);
    try {
      // `requestFullMetadata: false` strip EXIF/GPS dès la lecture par le
      // plugin — un avatar n'a aucune raison d'embarquer les coordonnées
      // GPS du cabinet du praticien.
      // `imageQuality: 90` + `maxWidth/maxHeight` plafonnent la résolution
      // côté plugin avant même que les bytes ne reviennent en Dart, ce qui
      // réduit drastiquement la pression mémoire sur smartphones d'entrée
      // de gamme. Le pipeline `ImageCompress` côté repo finalise.
      final XFile? picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      if (picked == null) {
        // L'utilisateur a annulé — pas une erreur.
        return;
      }
      final bytes = await picked.readAsBytes();
      final mime = _mimeFor(picked);
      final filename = _safeFilename(picked.name);
      await _commit(bytes: bytes, mime: mime, filename: filename);
      if (mounted) {
        showFloatingSnack(
          context,
          l10n.avatarUpdatedSnack,
          tone: SnackTone.success,
        );
      }
    } on AttachmentTooLargeError {
      if (mounted) {
        showFloatingSnack(
          context,
          l10n.attachmentsTooLarge,
          tone: SnackTone.error,
        );
      }
    } on AttachmentRejectedError catch (e) {
      if (mounted) {
        final msg = e.reason == 'image_too_large'
            ? l10n.attachmentsImageTooLarge
            : l10n.attachmentsRejectedImage;
        showFloatingSnack(context, msg, tone: SnackTone.error);
      }
    } on Object {
      // Aucun chemin n'expose `e.toString()` à l'UI : message générique
      // `avatarErrorImport` (cf. pattern Files Tech `errorView`).
      if (mounted) {
        showFloatingSnack(
          context,
          l10n.avatarErrorImport,
          tone: SnackTone.error,
        );
      }
    } finally {
      // Wipe immédiat des caches `image_picker` : le plugin a copié l'original
      // dans `cache/image_picker/<uuid>.jpg` avant de retourner les bytes.
      // Maintenant que l'avatar est chiffré et persisté (ou que l'utilisateur
      // a annulé), l'original en clair n'a plus à exister.
      unawaited(_purgeImagePickerCache());
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit({
    required Uint8List bytes,
    required String mime,
    required String filename,
  }) async {
    final ctrl = widget.controller;
    if (_isDeferred && ctrl != null) {
      // Mode différé : on stocke dans le controller, le form `commit`
      // appellera `setAvatar` après `repo.create(draft)`.
      ctrl._setPending(bytes: bytes, mimeType: mime, filename: filename);
      return;
    }
    if (widget.ownerId.isEmpty) {
      // Garde-fou : sans controller ET sans ownerId, on ne peut rien faire.
      return;
    }
    final repo = ref.read(attachmentRepositoryProvider);
    await repo.setAvatar(
      ownerType: widget.ownerType,
      ownerId: widget.ownerId,
      bytes: bytes,
      mimeType: mime,
      filename: filename,
    );
  }

  Future<void> _confirmAndRemove() async {
    final l10n = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;
    // Confirmation modale : une suppression d'avatar n'a pas de poubelle,
    // c'est immédiat (si en mode immédiat) ou pris en compte au save (si
    // en mode différé).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.avatarRemove),
        content: Text(l10n.avatarRemoveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            autofocus: true,
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final ctrl = widget.controller;
      if (_isDeferred && ctrl != null) {
        ctrl._requestRemove();
      } else if (widget.ownerId.isNotEmpty) {
        await ref
            .read(attachmentRepositoryProvider)
            .clearAvatar(
              ownerType: widget.ownerType,
              ownerId: widget.ownerId,
            );
      }
      if (mounted) {
        showFloatingSnack(context, l10n.avatarRemovedSnack);
      }
    } on Object {
      if (mounted) {
        showFloatingSnack(
          context,
          l10n.avatarErrorImport,
          tone: SnackTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _mimeFor(XFile file) {
    final mime = file.mimeType;
    if (mime != null && mime.startsWith('image/')) return mime;
    final lower = file.name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    // image_picker capture caméra renvoie toujours JPEG sur Android.
    return 'image/jpeg';
  }

  /// Nettoie le filename : on retire les separateurs de chemin et les
  /// espaces, on cap à 120 chars (la valeur stockée est chiffrée — pas
  /// critique mais on évite les noms exotiques). Le nom n'apparait plus
  /// côté UI (la fiche affiche la photo seule) ; on le conserve pour
  /// traçabilité et l'export RGPD éventuel.
  static String _safeFilename(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/]'), '_')
        .replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return 'avatar.jpg';
    if (cleaned.length > 120) {
      return cleaned.substring(cleaned.length - 120);
    }
    return cleaned;
  }

  /// Purge les fichiers laissés par image_picker dans `cache/image_picker/`.
  /// Le plugin n'expose pas d'API officielle équivalente à
  /// `FilePicker.platform.clearTemporaryFiles()` ; on supprime donc
  /// manuellement, best-effort. Important pour ne pas laisser une photo
  /// du praticien (ou d'un client identifiable) trainer en clair sur disque.
  static Future<void> _purgeImagePickerCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final pickerDir = Directory(p.join(tempDir.path, 'image_picker'));
      if (!pickerDir.existsSync()) return;
      await for (final entity in pickerDir.list(recursive: true)) {
        if (entity is File) {
          try {
            await entity.delete();
          } on FileSystemException {
            // best-effort : un file lock OS ne doit pas faire foirer
            // le reste du wipe.
          }
        }
      }
    } on Object {
      // best-effort : un cache résiduel n'est pas un échec utilisateur.
    }
  }
}

/// Contrôleur portable pour l'usage différé d'`AvatarPicker` (création
/// d'entité). Le formulaire instancie ce contrôleur, le passe au picker,
/// puis appelle `commit(...)` après le `repo.create(draft)` initial pour
/// matérialiser l'avatar côté DB.
///
/// Le contrôleur est un value-holder côté UI : aucune dépendance Riverpod
/// au constructor. Il expose un mini-callback pour rebuild la preview.
class AvatarPickerController {
  AvatarPickerController();

  Uint8List? _pendingBytes;
  String? _pendingMime;
  String? _pendingFilename;
  bool _removeRequested = false;
  VoidCallback? _onChange;

  /// Bytes en attente d'écriture (mode différé). `null` quand aucune photo
  /// n'a été choisie (ou que l'utilisateur a demandé une suppression).
  Uint8List? get pendingBytes => _pendingBytes;
  String? get pendingMimeType => _pendingMime;
  String? get pendingFilename => _pendingFilename;

  /// `true` quand l'utilisateur a explicitement demandé la suppression de
  /// l'avatar pendant l'édition.
  bool get removeRequested => _removeRequested;

  /// `true` quand le picker a quelque chose à faire au commit (nouvelle
  /// photo OU demande de suppression).
  bool get hasPendingChange => _pendingBytes != null || _removeRequested;

  void _attach(VoidCallback cb) {
    _onChange = cb;
  }

  void _detach() {
    _onChange = null;
  }

  /// Libère l'éventuel buffer en RAM. Idempotent : appelable plusieurs fois
  /// sans risque (réinitialise simplement les champs). Convention alignée
  /// avec `TextEditingController.dispose()` pour que le formulaire puisse
  /// l'invoquer au sein de sa boucle `dispose()` sans cas particulier.
  void dispose() {
    _pendingBytes = null;
    _pendingMime = null;
    _pendingFilename = null;
    _removeRequested = false;
    _onChange = null;
  }

  void _setPending({
    required Uint8List bytes,
    required String mimeType,
    required String filename,
  }) {
    _pendingBytes = bytes;
    _pendingMime = mimeType;
    _pendingFilename = filename;
    _removeRequested = false;
    _onChange?.call();
  }

  void _requestRemove() {
    _pendingBytes = null;
    _pendingMime = null;
    _pendingFilename = null;
    _removeRequested = true;
    _onChange?.call();
  }

  /// Applique l'éventuel changement en attente sur l'entité fraîchement
  /// créée. Idempotent : sans changement à propager, ne fait rien.
  /// Appelée par le formulaire APRÈS `repo.create(draft)` quand l'`ownerId`
  /// final devient connu.
  Future<void> commit({
    required WidgetRef ref,
    required String ownerType,
    required String ownerId,
  }) async {
    if (!hasPendingChange) return;
    final repo = ref.read(attachmentRepositoryProvider);
    if (_pendingBytes != null) {
      await repo.setAvatar(
        ownerType: ownerType,
        ownerId: ownerId,
        bytes: _pendingBytes!,
        mimeType: _pendingMime!,
        filename: _pendingFilename!,
      );
    } else if (_removeRequested) {
      await repo.clearAvatar(ownerType: ownerType, ownerId: ownerId);
    }
    // Reset après commit.
    _pendingBytes = null;
    _pendingMime = null;
    _pendingFilename = null;
    _removeRequested = false;
  }
}

enum _AvatarAction { camera, gallery, remove }

/// Petit helper pour rendre une image circulaire à partir de bytes en RAM
/// — utilisé dans la preview du picker en mode différé (pas encore en DB).
class _CircleImage extends StatelessWidget {
  const _CircleImage({
    required this.bytes,
    required this.radius,
    required this.scheme,
  });

  final Uint8List bytes;
  final double radius;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cap = (radius * 2 * dpr * 2).round();
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.surfaceContainerHigh,
      foregroundImage: ResizeImage(
        MemoryImage(bytes),
        width: cap,
        policy: ResizeImagePolicy.fit,
      ),
    );
  }
}

/// Variante de la preview qui consomme `attachmentBytesProvider` — en mode
/// immédiat, après écriture, l'avatar arrive ici via le stream.
class _AvatarImageFromProvider extends ConsumerWidget {
  const _AvatarImageFromProvider({
    required this.attachmentId,
    required this.radius,
    required this.fallback,
  });

  final String attachmentId;
  final double radius;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final asyncBytes = ref.watch(attachmentBytesProvider(attachmentId));
    return asyncBytes.when(
      loading: () => fallback,
      error: (_, _) => fallback,
      data: (bytes) =>
          _CircleImage(bytes: bytes, radius: radius, scheme: scheme),
    );
  }
}
