import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/tag.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/error_view.dart';

/// Inline tag editor: shows current tags as deletable chips and an Autocomplete
/// input that creates a new tag (or reuses an existing one) on submit.
class TagEditor extends ConsumerWidget {
  const TagEditor({super.key, required this.ownerType, required this.ownerId});

  final String ownerType;
  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final repo = ref.watch(tagRepositoryProvider);
    final attached = ref.watch(
      _attachedTagsProvider((ownerType: ownerType, ownerId: ownerId)),
    );
    final all = ref.watch(allTagsProvider);
    return attached.when(
      loading: () => const SizedBox(height: 32),
      error: (e, _) => Text(localiseError(context, e)),
      data: (tags) {
        final attachedIds = tags.map((t) => t.id).toSet();
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final t in tags)
              InputChip(
                label: Text(t.label),
                onDeleted: () => repo.unlink(
                  tagId: t.id,
                  ownerType: ownerType,
                  ownerId: ownerId,
                ),
              ),
            SizedBox(
              width: 200,
              child: Autocomplete<Tag>(
                displayStringForOption: (t) => t.label,
                optionsBuilder: (input) {
                  final q = input.text.trim().toLowerCase();
                  if (q.isEmpty) return const Iterable<Tag>.empty();
                  return (all.valueOrNull ?? const <Tag>[]).where(
                    (t) =>
                        !attachedIds.contains(t.id) &&
                        t.label.toLowerCase().contains(q),
                  );
                },
                fieldViewBuilder:
                    (ctx, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          hintText: l10n.tagsAddHint,
                          isDense: true,
                        ),
                        onSubmitted: (value) async {
                          final v = value.trim();
                          if (v.isEmpty) return;
                          final tag = await repo.upsert(label: v);
                          await repo.link(
                            tagId: tag.id,
                            ownerType: ownerType,
                            ownerId: ownerId,
                          );
                          controller.clear();
                        },
                      );
                    },
                onSelected: (t) async {
                  await repo.link(
                    tagId: t.id,
                    ownerType: ownerType,
                    ownerId: ownerId,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

typedef _OwnerKey = ({String ownerType, String ownerId});

final _attachedTagsProvider = StreamProvider.family<List<Tag>, _OwnerKey>((
  ref,
  key,
) {
  return ref
      .watch(tagRepositoryProvider)
      .watchForOwner(ownerType: key.ownerType, ownerId: key.ownerId);
});
