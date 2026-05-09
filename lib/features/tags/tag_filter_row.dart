import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/tag.dart';

/// Horizontal scrollable row of FilterChips bound to a [StateProvider]
/// of selected tag ids. Reusable across clients/animals/sessions lists.
class TagFilterRow extends ConsumerWidget {
  const TagFilterRow({super.key, required this.selectionProvider});

  /// The provider that holds the current selection.
  final StateProvider<Set<String>> selectionProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(_allTagsProvider);
    final selected = ref.watch(selectionProvider);
    return tags.when(
      loading: () => const SizedBox(height: 44),
      error: (e, _) => Text('$e'),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 44,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            children: [
              for (final t in list) ...[
                FilterChip(
                  label: Text(t.label),
                  selected: selected.contains(t.id),
                  onSelected: (s) {
                    final next = {...selected};
                    if (s) {
                      next.add(t.id);
                    } else {
                      next.remove(t.id);
                    }
                    ref.read(selectionProvider.notifier).state = next;
                  },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

final _allTagsProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(tagRepositoryProvider).watchAll();
});
