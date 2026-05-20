import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../domain/animal.dart';
import '../../domain/attachment.dart';
import '../../domain/tag.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/date_format.dart';
import '../../widgets/confirm_delete_dialog.dart';
import '../../widgets/detail_section_card.dart';
import '../../widgets/error_view.dart';
import '../../widgets/owner_avatar.dart';
import '../../widgets/snack_utils.dart';
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
      error: (e, _) => ErrorView(error: e),
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
              tooltip: l10n.actionEdit,
              onPressed: () => _edit(context, ref),
            ),
            IconButton(
              // (audit UI H1) cs.error pour cohérence cross-écrans avec
              // session_detail / appointment_form. Icône destructive →
              // rouge sémantique Material 3.
              icon: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              tooltip: l10n.actionDelete,
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
        // Photo-avatar lecture seule au sommet de la fiche : tap → viewer
        // plein écran. L'édition se fait via le bouton « Modifier » qui
        // ouvre `AnimalFormScreen` (lui-même intègre `AvatarPicker`).
        Center(
          child: OwnerAvatar(
            ownerType: AttachmentOwner.animal,
            ownerId: animal.id,
            radius: 48,
            tappableForView: true,
            fallbackChild: Icon(
              Icons.pets_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TagEditor(ownerType: TagOwner.animal, ownerId: animal.id),
        const SizedBox(height: 12),
        DetailRow(
          icon: Icons.pets,
          text:
              '${speciesLabel(l10n, animal.species)}'
              '${animal.breed == null ? '' : ' · ${animal.breed}'}',
        ),
        if (animal.sex != null && animal.sex != AnimalSex.unknown)
          DetailRow(icon: Icons.male, text: sexLabel(l10n, animal.sex)),
        if (animal.ageYears != null)
          DetailRow(icon: Icons.cake_outlined, text: '${animal.ageYears} ans'),
        if (animal.weightKg != null)
          DetailRow(
            icon: Icons.monitor_weight_outlined,
            text: '${animal.weightKg!.toStringAsFixed(1)} kg',
          ),
        if (animal.color != null)
          DetailRow(icon: Icons.palette_outlined, text: animal.color!),
        if (animal.identifiers.chipNumber.isNotEmpty ||
            animal.identifiers.tattooNumber.isNotEmpty ||
            animal.identifiers.pedigreeNumber.isNotEmpty) ...[
          const SizedBox(height: 16),
          DetailSectionCard(
            title: l10n.animalFormSectionIdentifiers,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (animal.identifiers.chipNumber.isNotEmpty)
                  Text(
                    '${l10n.animalFormChip} : '
                    '${animal.identifiers.chipNumber}',
                  ),
                if (animal.identifiers.tattooNumber.isNotEmpty)
                  Text(
                    '${l10n.animalFormTattoo} : '
                    '${animal.identifiers.tattooNumber}',
                  ),
                if (animal.identifiers.pedigreeNumber.isNotEmpty)
                  Text(
                    '${l10n.animalFormPedigree} : '
                    '${animal.identifiers.pedigreeNumber}',
                  ),
              ],
            ),
          ),
        ],
        if (animal.identifiers.hasVet) ...[
          const SizedBox(height: 16),
          _VetCard(identifiers: animal.identifiers),
        ],
        if (animal.identifiers.hasVaccination) ...[
          const SizedBox(height: 16),
          _VaccinationCard(identifiers: animal.identifiers),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (animal != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => SessionFormScreen(
                        defaultClientId: animal.clientId,
                        defaultAnimalId: animalId,
                      ),
                      fullscreenDialog: true,
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.actionAdd),
                ),
              ],
            ),
          ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e),
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
                        title: Text(formatDate(s.startAt)),
                        subtitle: Text(
                          '${kindLabel(l10n, s.kind)} · '
                          '${statusLabel(l10n, s.status)}',
                        ),
                        // (audit M6) Onglet sessions de l'animal :
                        // tap → sélection + navigation cohérente avec
                        // l'onglet sessions du client (qui le faisait
                        // déjà). Avant : tile inerte.
                        onTap: () {
                          ref.read(selectedSessionIdProvider.notifier).state =
                              s.id;
                        },
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// Card vétérinaire (animal_detail). Affichée seulement si au moins un
/// champ vétérinaire structuré est renseigné. Tap téléphone → `tel:` /
/// tap email → `mailto:` via `url_launcher`. Plus de `Clipboard.setData`
/// (qui exposait les coordonnées du véto aux listeners clavier et à la
/// notif système Android 12+ — audit v1.6.0 F1).
class _VetCard extends StatelessWidget {
  const _VetCard({required this.identifiers});
  final AnimalIdentifiers identifiers;

  /// Lance une URI externe (`tel:` ou `mailto:`). Messenger capturé AVANT
  /// l'await pour éviter le pattern fragile « accès context après gap »
  /// (audit v1.6.0 P5).
  Future<void> _launch(
    BuildContext context,
    Uri uri,
    String fallbackErrorLabel,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    bool ok;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(
        buildFloatingSnack(fallbackErrorLabel, scheme, tone: SnackTone.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return DetailSectionCard(
      title: l10n.animalFormSectionVet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (identifiers.vetName.isNotEmpty)
            _row(context, Icons.person_outline, identifiers.vetName),
          if (identifiers.vetClinic.isNotEmpty)
            _row(context, Icons.local_hospital_outlined, identifiers.vetClinic),
          if (identifiers.vetPhone.isNotEmpty)
            _row(
              context,
              Icons.phone_outlined,
              identifiers.vetPhone,
              onTap: () => _launch(
                context,
                Uri(scheme: 'tel', path: identifiers.vetPhone),
                l10n.animalDetailVetLaunchFailed,
              ),
              tooltip: l10n.animalDetailVetCallTooltip,
            ),
          if (identifiers.vetEmail.isNotEmpty)
            _row(
              context,
              Icons.email_outlined,
              identifiers.vetEmail,
              onTap: () => _launch(
                context,
                Uri(scheme: 'mailto', path: identifiers.vetEmail),
                l10n.animalDetailVetLaunchFailed,
              ),
              tooltip: l10n.animalDetailVetEmailTooltip,
            ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String text, {
    VoidCallback? onTap,
    String? tooltip,
  }) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      child: Tooltip(message: tooltip ?? '', child: child),
    );
  }
}

/// Card vaccination — dernière date, prochaine date avec mise en évidence
/// rouge si dépassée, notes facultatives. Aligné sur `DetailSectionCard`
/// pour conserver la cohérence visuelle avec les autres sections.
class _VaccinationCard extends StatelessWidget {
  const _VaccinationCard({required this.identifiers});
  final AnimalIdentifiers identifiers;

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;
    final overdue = identifiers.nextVaccinationOverdue;
    return DetailSectionCard(
      title: l10n.animalFormSectionVaccination,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (identifiers.lastVaccinationAt != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${l10n.animalDetailVaccinationLastLabel} : '
                '${_fmt(identifiers.lastVaccinationAt!)}',
              ),
            ),
          if (identifiers.nextVaccinationAt != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: overdue
                  // Mention "À renouveler" : associe une icône
                  // `warning_amber_outlined` au texte pour ne pas faire
                  // reposer le signal d'alerte uniquement sur la couleur
                  // (audit v1.6.0 U10 — a11y daltonien).
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 18,
                          color: cs.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l10n.animalDetailVaccinationOverdue(
                              _fmt(identifiers.nextVaccinationAt!),
                            ),
                            style: TextStyle(
                              color: cs.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '${l10n.animalDetailVaccinationNextLabel} : '
                      '${_fmt(identifiers.nextVaccinationAt!)}',
                    ),
            ),
          if (identifiers.vaccinationNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(identifiers.vaccinationNotes),
          ],
        ],
      ),
    );
  }
}
