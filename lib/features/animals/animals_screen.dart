import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/animal.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/breakpoints.dart';
import '../../widgets/error_view.dart';
import '../tags/tag_filter_row.dart';
import 'animal_detail_screen.dart';
import 'animal_form_screen.dart';
import 'animal_l10n.dart';
import 'animal_providers.dart';

class AnimalsScreen extends ConsumerWidget {
  const AnimalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Stack(
      children: [
        MasterDetailLayout(list: _AnimalsList(), detail: AnimalDetailScreen()),
        Positioned(right: 16, bottom: 16, child: _AddAnimalFab()),
      ],
    );
  }
}

class _AddAnimalFab extends ConsumerWidget {
  const _AddAnimalFab();

  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const AnimalFormScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return FloatingActionButton.extended(
      onPressed: () => _open(context),
      icon: const Icon(Icons.add),
      label: Text(l10n.actionAdd),
    );
  }
}

class _AnimalsList extends ConsumerWidget {
  const _AnimalsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final list = ref.watch(animalsStreamProvider);
    final species = ref.watch(animalsSpeciesFilterProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.actionSearch,
            ),
            onChanged: (v) => ref.read(animalsQueryProvider.notifier).state = v,
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            children: [
              ChoiceChip(
                label: Text(l10n.speciesOther),
                selected: species == null,
                onSelected: (_) =>
                    ref.read(animalsSpeciesFilterProvider.notifier).state =
                        null,
              ),
              const SizedBox(width: 8),
              for (final s in Species.all) ...[
                ChoiceChip(
                  label: Text(speciesLabel(l10n, s)),
                  selected: species == s,
                  onSelected: (sel) =>
                      ref.read(animalsSpeciesFilterProvider.notifier).state =
                          sel ? s : null,
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        TagFilterRow(selectionProvider: animalsTagFilterProvider),
        const SizedBox(height: 4),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e),
            data: (animals) => animals.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text(l10n.animalsListEmpty)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: animals.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _AnimalTile(animal: animals[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _AnimalTile extends ConsumerWidget {
  const _AnimalTile({required this.animal});
  final Animal animal;

  IconData get _icon => switch (animal.species) {
    Species.dog => Icons.pets,
    Species.cat => Icons.pets,
    Species.horse => Icons.directions_run,
    Species.bird => Icons.flutter_dash,
    _ => Icons.pets_outlined,
  };

  Future<void> _select(BuildContext context, WidgetRef ref) async {
    ref.read(selectedAnimalIdProvider.notifier).state = animal.id;
    if (context.isCompact) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const AnimalDetailScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final selectedId = ref.watch(selectedAnimalIdProvider);
    return ListTile(
      selected: selectedId == animal.id,
      leading: CircleAvatar(child: Icon(_icon)),
      title: Text(animal.name),
      subtitle: Text(
        [
          speciesLabel(l10n, animal.species),
          if (animal.breed != null && animal.breed!.isNotEmpty) animal.breed,
        ].whereType<String>().join(' · '),
      ),
      onTap: () => _select(context, ref),
    );
  }
}
