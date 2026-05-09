import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../domain/attachment.dart';
import '../../l10n/generated/app_localizations.dart';
import 'attachment_viewer.dart';

/// Reusable attachments section embedded in client / animal / session detail
/// screens. Provider-family keyed by `(ownerType, ownerId)` so multiple
/// instances on the same screen don't fight each other.
class AttachmentsSection extends ConsumerWidget {
  const AttachmentsSection({
    super.key,
    required this.ownerType,
    required this.ownerId,
  });

  final String ownerType;
  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final stream = ref.watch(_attachmentsByOwnerProvider((
      ownerType: ownerType,
      ownerId: ownerId,
    )));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _import(
                  context: context,
                  ref: ref,
                  kind: AttachmentKind.photo,
                  fileType: FileType.image,
                ),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.attachmentsAddPhoto),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _import(
                  context: context,
                  ref: ref,
                  kind: AttachmentKind.document,
                  fileType: FileType.any,
                ),
                icon: const Icon(Icons.attach_file),
                label: Text(l10n.attachmentsAddDocument),
              ),
            ],
          ),
        ),
        Expanded(
          child: stream.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) => list.isEmpty
                ? Center(child: Text(l10n.attachmentsEmpty))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _AttachmentTile(
                      attachment: list[i],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _import({
    required BuildContext context,
    required WidgetRef ref,
    required String kind,
    required FileType fileType,
  }) async {
    final l10n = AppL10n.of(context);
    final picked = await FilePicker.platform.pickFiles(
      type: fileType,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;

    final mime = _guessMime(file.name);
    try {
      await ref.read(attachmentRepositoryProvider).importBytes(
            ownerType: ownerType,
            ownerId: ownerId,
            kind: kind,
            filename: file.name,
            mimeType: mime,
            bytes: bytes,
          );
    } on AttachmentTooLargeError {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.attachmentsTooLarge)),
      );
    } on AttachmentRejectedError {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.attachmentsRejectedImage)),
      );
    }
  }

  static String _guessMime(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }
}

class _AttachmentTile extends ConsumerWidget {
  const _AttachmentTile({required this.attachment});
  final Attachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(
        attachment.isImage ? Icons.image_outlined : Icons.description_outlined,
      ),
      title: Text(attachment.filename),
      subtitle: Text(_formatSize(attachment.sizeBytes)),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          if (action == 'delete') {
            await ref.read(attachmentRepositoryProvider).purge(attachment.id);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'delete', child: Text('Supprimer')),
        ],
      ),
      onTap: () {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => AttachmentViewer(attachment: attachment),
          ),
        );
      },
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

typedef _OwnerKey = ({String ownerType, String ownerId});

final _attachmentsByOwnerProvider = StreamProvider.family<
    List<Attachment>, _OwnerKey>((ref, key) {
  return ref.watch(attachmentRepositoryProvider).watchByOwner(
        ownerType: key.ownerType,
        ownerId: key.ownerId,
      );
});
