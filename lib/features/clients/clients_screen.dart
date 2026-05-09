import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/client.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/breakpoints.dart';
import '../../widgets/disclaimer_dialog.dart';
import '../tags/tag_filter_row.dart';
import 'client_detail_screen.dart';
import 'client_form_screen.dart';
import 'client_providers.dart';

/// Top-level clients screen. Phone shows list-only; tablet shows the
/// master-detail layout with the detail pane bound to the selection.
class ClientsScreen extends ConsumerWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Stack(
      children: [
        MasterDetailLayout(list: _ClientsList(), detail: ClientDetailScreen()),
        Positioned(right: 16, bottom: 16, child: _AddClientFab()),
      ],
    );
  }
}

class _AddClientFab extends ConsumerWidget {
  const _AddClientFab();

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final accepted = await DisclaimerDialog.show(context);
    if (!accepted || !context.mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const ClientFormScreen(),
        fullscreenDialog: true,
      ),
    );
    // List auto-refreshes via Drift stream.
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return FloatingActionButton.extended(
      onPressed: () => _open(context, ref),
      icon: const Icon(Icons.person_add_alt),
      label: Text(l10n.actionAdd),
    );
  }
}

class _ClientsList extends ConsumerWidget {
  const _ClientsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final list = ref.watch(clientsStreamProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.clientsListSearchHint,
            ),
            onChanged: (v) => ref.read(clientsQueryProvider.notifier).state = v,
          ),
        ),
        TagFilterRow(selectionProvider: clientsTagFilterProvider),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (clients) => clients.isEmpty
                ? _Empty(text: l10n.clientsListEmpty)
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: clients.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _ClientTile(client: clients[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ClientTile extends ConsumerWidget {
  const _ClientTile({required this.client});
  final Client client;

  String get _initials {
    final f = client.firstName.isEmpty ? '' : client.firstName[0];
    final l = client.lastName.isEmpty ? '' : client.lastName[0];
    return (f + l).toUpperCase();
  }

  Future<void> _select(BuildContext context, WidgetRef ref) async {
    ref.read(selectedClientIdProvider.notifier).state = client.id;
    if (context.isCompact) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const ClientDetailScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedClientIdProvider);
    return ListTile(
      selected: selectedId == client.id,
      leading: CircleAvatar(child: Text(_initials)),
      title: Text(client.fullName),
      subtitle: Text(
        [
          client.email,
          client.phone,
        ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
      ),
      onTap: () => _select(context, ref),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}
