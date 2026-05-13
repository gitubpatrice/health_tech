import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/attachment.dart';
import '../../domain/client.dart';
import '../../domain/tag.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/date_format.dart';
import '../../widgets/confirm_delete_dialog.dart';
import '../../widgets/detail_section_card.dart';
import '../../widgets/error_view.dart';
import '../animals/animal_form_screen.dart';
import '../animals/animal_l10n.dart';
import '../animals/animal_providers.dart';
import '../attachments/attachments_section.dart';
import '../sessions/session_form_screen.dart';
import '../sessions/session_l10n.dart';
import '../sessions/session_providers.dart';
import '../tags/tag_editor.dart';
import 'client_form_screen.dart';
import 'client_providers.dart';

/// Tabbed view for a client. The 4 tabs (Info / Animals / Sessions /
/// Attachments) all share the same selected-client provider, so swapping
/// tabs is instant once data has been resolved.
class ClientDetailScreen extends ConsumerWidget {
  const ClientDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final selected = ref.watch(selectedClientProvider);
    return selected.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e),
      data: (client) => client == null
          ? Center(child: Text(l10n.clientDetailNoSelection))
          : _ClientTabbed(client: client),
    );
  }
}

class _ClientTabbed extends ConsumerWidget {
  const _ClientTabbed({required this.client});
  final Client client;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ClientFormScreen(initial: client),
        fullscreenDialog: true,
      ),
    );
    if (updated == true) ref.invalidate(selectedClientProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final confirmed = await showConfirmDeleteDialog(
      context,
      title: l10n.clientDetailDeleteTitle,
      body: l10n.clientDetailDeleteBody,
    );
    if (!confirmed) return;
    await ref.read(purgeServiceProvider).softDeleteClient(client.id);
    ref.read(selectedClientIdProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(client.fullName),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10n.actionEdit,
              onPressed: () => _edit(context, ref),
            ),
            IconButton(
              // (audit UI H1) Cohérence cross-écrans : icône destructive
              // teinte `cs.error` partout (session_detail, animal_detail,
              // appointment_form).
              icon: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              tooltip: l10n.actionDelete,
              onPressed: () => _delete(context, ref),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: const Icon(Icons.info_outline), text: l10n.tabInfo),
              Tab(icon: const Icon(Icons.pets), text: l10n.tabAnimals),
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
            _InfoTab(client: client),
            _AnimalsTab(clientId: client.id),
            _SessionsTab(clientId: client.id),
            AttachmentsSection(
              ownerType: AttachmentOwner.client,
              ownerId: client.id,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.client});
  final Client client;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TagEditor(ownerType: TagOwner.client, ownerId: client.id),
        const SizedBox(height: 12),
        if (client.isBusiness) ...[
          if ((client.business['siret'] as String?)?.isNotEmpty ?? false)
            DetailRow(
              icon: Icons.business_outlined,
              text: 'SIRET ${client.business['siret']}',
            ),
          if ((client.business['siren'] as String?)?.isNotEmpty ?? false)
            DetailRow(
              icon: Icons.business_outlined,
              text: 'SIREN ${client.business['siren']}',
            ),
          if ((client.profile['geobiology'] as bool?) ?? false)
            DetailRow(
              icon: Icons.terrain_outlined,
              text: l10n.clientFormGeobiology,
            ),
          if ((client.profile['em_waves'] as bool?) ?? false)
            DetailRow(icon: Icons.waves_outlined, text: l10n.clientFormEmWaves),
        ] else if (client.profession != null && client.profession!.isNotEmpty)
          DetailRow(icon: Icons.work_outline, text: client.profession!),
        if (client.phone != null && client.phone!.isNotEmpty)
          DetailRow(icon: Icons.phone_outlined, text: client.phone!),
        if (client.email != null && client.email!.isNotEmpty)
          DetailRow(icon: Icons.email_outlined, text: client.email!),
        if (!client.address.isEmpty)
          DetailRow(
            icon: Icons.location_on_outlined,
            text: _formatAddress(client),
          ),
        if (!client.isBusiness && client.ageYears != null)
          DetailRow(icon: Icons.cake_outlined, text: '${client.ageYears} ans'),
        if (client.healthNotes.isNotEmpty) ...[
          const SizedBox(height: 16),
          DetailSectionCard(
            title: client.isBusiness
                ? l10n.clientFormSurveyNotes
                : l10n.clientFormSectionHealth,
            child: Text(client.healthNotes),
          ),
        ],
        if (client.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          DetailSectionCard(
            title: client.isBusiness
                ? l10n.clientFormRecommendations
                : l10n.clientFormFreeNotes,
            child: Text(client.notes),
          ),
        ],
      ],
    );
  }

  String _formatAddress(Client c) {
    final parts = <String>[
      if (c.address.street.isNotEmpty) c.address.street,
      if (c.address.complement.isNotEmpty) c.address.complement,
      [
        c.address.zipCode,
        c.address.city,
      ].where((s) => s.isNotEmpty).join(' ').trim(),
      if (c.address.region.isNotEmpty) c.address.region,
      if (c.address.country.isNotEmpty && c.address.country != 'FR')
        c.address.country,
    ].where((s) => s.isNotEmpty).toList();
    return parts.join('\n');
  }
}

class _AnimalsTab extends ConsumerWidget {
  const _AnimalsTab({required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final list = ref.watch(animalsByClientProvider(clientId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => AnimalFormScreen(defaultClientId: clientId),
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
            data: (animals) => animals.isEmpty
                ? Center(child: Text(l10n.animalsListEmpty))
                : ListView.separated(
                    itemCount: animals.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = animals[i];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.pets)),
                        title: Text(a.name),
                        subtitle: Text(speciesLabel(l10n, a.species)),
                        onTap: () {
                          ref.read(selectedAnimalIdProvider.notifier).state =
                              a.id;
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

class _SessionsTab extends ConsumerWidget {
  const _SessionsTab({required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final list = ref.watch(sessionsByClientProvider(clientId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) =>
                        SessionFormScreen(defaultClientId: clientId),
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
