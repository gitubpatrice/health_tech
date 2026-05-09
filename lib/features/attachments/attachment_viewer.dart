import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/attachment.dart';

/// Decrypts an attachment in memory and displays it. Used for both images
/// (rendered with [Image.memory]) and other files (a placeholder + filename
/// for now; v0.5 will route documents through `share_plus` for the system
/// viewer).
class AttachmentViewer extends ConsumerWidget {
  const AttachmentViewer({super.key, required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = ref.watch(_decryptedProvider(attachment.id));
    return Scaffold(
      appBar: AppBar(title: Text(attachment.filename)),
      body: future.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (bytes) => attachment.isImage
            ? _ImageBody(bytes: bytes)
            : _OpaqueBody(attachment: attachment, bytes: bytes),
      ),
    );
  }
}

class _ImageBody extends StatelessWidget {
  const _ImageBody({required this.bytes});
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) {
    // cacheWidth caps the decoded bitmap size so a 12 MP photo doesn't allocate
    // ~48 MB of RGBA on low-end devices. Users can zoom via InteractiveViewer
    // for fine detail without paying full-resolution decode upfront.
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (size.width * dpr).round();
    return InteractiveViewer(
      maxScale: 6,
      child: Center(
        child: Image.memory(
          bytes,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class _OpaqueBody extends StatelessWidget {
  const _OpaqueBody({required this.attachment, required this.bytes});
  final Attachment attachment;
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.description_outlined, size: 64),
          const SizedBox(height: 16),
          Text(attachment.filename),
          const SizedBox(height: 8),
          Text('${bytes.length} bytes'),
        ],
      ),
    );
  }
}

/// Family provider — keyed by attachment id so multiple viewers can coexist
/// (and so the cache is reused if the user reopens the same attachment).
final _decryptedProvider = FutureProvider.family<Uint8List, String>((
  ref,
  id,
) async {
  return ref.watch(attachmentRepositoryProvider).readBytes(id);
});
