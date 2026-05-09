import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/animal.dart';
import '../../domain/attachment.dart';
import '../../domain/tag.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/confirm_delete_dialog.dart';
import '../../widgets/detail_section_card.dart';
import '../attachments/attachments_section.dart';
import '../sessions/session_form_screen.dart';
import '../sessions/session_l10n.dart';
import '../sessions/session_providers.dart';
import '../tags/tag_editor.dart';
import 'animal_form_screen.dart';
import 'animal_l10n.dart';
import 'animal_providers.dart';

class AnimalDetailScreen extends ConsumerWidget {
  const AnimalDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final selected = ref.watch(selectedAnimalProvider);
    return selected.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (animal) => animal == null
          ? Center(child: Text(l10n.animalDetailNoSelection))
          : _AnimalTabbed(animal: animal),
    );
  }
}

class _AnimalTabbed extends ConsumerWidget {
  const _AnimalTabbed({required this.animal});
  final Animal animal;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AnimalFormScreen(initial: animal),
        fullscreenDialog: true,
      ),
    );
    if (updated == true) ref.invalidate(selectedAnimalProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final confirmed = await showConfirmDeleteDialog(
      context,
      title: l10n.animalDetailDeleteTitle,
      body: l10n.animalDetailDeleteBody,
    );
    if (!confirmed) return;
    await ref.read(purgeServiceProvider).softDeleteAnimal(animal.id);
    ref.read(selectedAnimalIdProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(animal.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _edit(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.info_outline), text: l10n.tabInfo),
              Tab(icon: const Icon(Icons.event_note), text: l10n.tabSessions),
              Tab(
                icon: const Icon(Icons.attach_file),
                text: l10n.tabAttachments,
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _InfoTab(animal: animal),
            _SessionsTab(animalId: animal.id),
            AttachmentsSection(
              ownerType: AttachmentOwner.animal,
              ownerId: animal.id,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.animal});
  final Animal animal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TagEditor(
          ownerType: TagOwner.animal,
          ownerId: animal.id,
        ),
        const SizedBox(height: 12),
        DetailRow(
          icon: Icons.pets,
          text: '${speciesLabel(l10n, animal.species)}'
              '${animal.breed == null ? '' : ' · ${animal.breed}'}',
        ),
        if (animal.sex != null && animal.sex != AnimalSex.unknown)
          DetailRow(icon: Icons.male, text: sexLabel(l10n, animal.sex)),
        if (animal.ageYears != null)
          DetailRow(
              icon: Icons.cake_outlined, text: '${animal.ageYears} ans'),
        if (animal.weightKg != null)
          DetailRow(
              icon: Icons.monitor_weight_outlined,
              text: '${animal.weightKg!.toStringAsFixed(1)} kg'),
        if (animal.color != null)
          DetailRow(icon: Icons.palette_outlined, text: animal.color!),
        if (!animal.identifiers.isEmpty) ...[
          const SizedBox(height: 16),
          DetailSectionCard(
            title: l10n.animalFormSectionIdentifiers,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (animal.identifiers.chipNumber.isNotEmpty)
                  Text('${l10n.animalFormChip} : '
                      '${animal.identifiers.chipNumber}'),
                if (animal.identifiers.tattooNumber.isNotEmpty)
                  Text('${l10n.animalFormTattoo} : '
                      '${animal.identifiers.tattooNumber}'),
                if (animal.identifiers.pedigreeNumber.isNotEmpty)
                  Text('${l10n.animalFormPedigree} : '
                      '${animal.identifiers.pedigreeNumber}'),
              ],
            ),
          ),
        ],
        if (animal.healthNotes.isNotEmpty) ...[
          const SizedBox(height: 16),
          DetailSectionCard(
            title: l10n.animalFormHealthNotes,
            child: Text(animal.healthNotes),
          ),
        ],
        if (animal.behaviorNotes.isNotEmpty) ...[
          const SizedBox(height: 16),
          DetailSectionCard(
            title: l10n.animalFormBehaviorNotes,
            child: Text(animal.behaviorNotes),
          ),
        ],
      ],
    );
  }
}

class _SessionsTab extends ConsumerWidget {
  const _SessionsTab({required this.animalId});
  final String animalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final list = ref.watch(sessionsByAnimalProvider(animalId));
    final animal = ref.watch(selectedAnimalProvider).valueOrNull;
    return Stack(
      children: [
        list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (sessions) => sessions.isEmpty
              ? Center(child: Text(l10n.sessionsListEmpty))
              : ListView.separated(
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = sessions[i];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.event_note),
                      ),
                      title: Text(
                        '${s.startAt.day.toString().padLeft(2, '0')}/'
                        '${s.startAt.month.toString().padLeft(2, '0')}/'
                        '${s.startAt.year}',
                      ),
                      subtitle: Text(
                        '${kindLabel(l10n, s.kind)} · '
                        '${statusLabel(l10n, s.status)}',
                      ),
                    );
                  },
                ),
        ),
        if (animal != null)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'add-session-animal-$animalId',
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => SessionFormScreen(
                    defaultClientId: animal.clientId,
                    defaultAnimalId: animalId,
                  ),
                  fullscreenDialog: true,
                ),
              ),
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }
}
