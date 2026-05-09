import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/attachment.dart';
import '../../domain/client.dart';
import '../../l10n/generated/app_localizations.dart';
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
      error: (e, _) => Center(child: Text('$e')),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.clientDetailDeleteTitle),
        content: Text(l10n.clientDetailDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(clientRepositoryProvider).softDelete(client.id);
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
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.actionDelete,
              onPressed: () => _delete(context, ref),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: const Icon(Icons.info_outline), text: l10n.tabInfo),
              Tab(icon: const Icon(Icons.pets), text: l10n.tabAnimals),
              Tab(
                  icon: const Icon(Icons.event_note),
                  text: l10n.tabSessions),
              Tab(
                  icon: const Icon(Icons.attach_file),
                  text: l10n.tabAttachments),
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
        TagEditor(
          ownerType: AttachmentOwner.client,
          ownerId: client.id,
        ),
        const SizedBox(height: 12),
        if (client.profession != null && client.profession!.isNotEmpty)
          _row(Icons.work_outline, client.profession!),
        if (client.phone != null && client.phone!.isNotEmpty)
          _row(Icons.phone_outlined, client.phone!),
        if (client.email != null && client.email!.isNotEmpty)
          _row(Icons.email_outlined, client.email!),
        if (!client.address.isEmpty)
          _row(Icons.location_on_outlined, _formatAddress(client)),
        if (client.ageYears != null)
          _row(Icons.cake_outlined, '${client.ageYears} ans'),
        if (client.healthNotes.isNotEmpty) ...[
          const SizedBox(height: 16),
          _section(
              context, l10n.clientFormSectionHealth, Text(client.healthNotes)),
        ],
        if (client.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          _section(
              context, l10n.clientFormFreeNotes, Text(client.notes)),
        ],
      ],
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      );

  Widget _section(BuildContext c, String title, Widget child) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(c).textTheme.titleMedium),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      );

  String _formatAddress(Client c) {
    final parts = <String>[
      if (c.address.street.isNotEmpty) c.address.street,
      if (c.address.complement.isNotEmpty) c.address.complement,
      [c.address.zipCode, c.address.city]
          .where((s) => s.isNotEmpty)
          .join(' ')
          .trim(),
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
    return Stack(
      children: [
        list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
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
                        ref
                            .read(selectedAnimalIdProvider.notifier)
                            .state = a.id;
                      },
                    );
                  },
                ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'add-animal-$clientId',
            onPressed: () => Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) =>
                    AnimalFormScreen(defaultClientId: clientId),
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

class _SessionsTab extends ConsumerWidget {
  const _SessionsTab({required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final list = ref.watch(sessionsByClientProvider(clientId));
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
                      onTap: () {
                        ref
                            .read(selectedSessionIdProvider.notifier)
                            .state = s.id;
                      },
                    );
                  },
                ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'add-session-$clientId',
            onPressed: () => Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) =>
                    SessionFormScreen(defaultClientId: clientId),
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
