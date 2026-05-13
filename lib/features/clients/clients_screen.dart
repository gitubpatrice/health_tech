import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/client.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/breakpoints.dart';
import '../../widgets/disclaimer_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
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
    final list = ref.watch(clientsStreamProvider);
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: _DebouncedSearchField(),
        ),
        TagFilterRow(selectionProvider: clientsTagFilterProvider),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e),
            data: (clients) => clients.isEmpty
                ? EmptyState(
                    icon: Icons.people_outline,
                    title: AppL10n.of(context).clientsListEmpty,
                  )
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

/// Barre de recherche débouncée — propage la valeur saisie au
/// `clientsQueryProvider` 250 ms après la dernière frappe. Évite de
/// relancer la requête SQL (FTS5 / LIKE) à chaque caractère pendant
/// la saisie (audit perf H4).
class _DebouncedSearchField extends ConsumerStatefulWidget {
  const _DebouncedSearchField();
  @override
  ConsumerState<_DebouncedSearchField> createState() =>
      _DebouncedSearchFieldState();
}

class _DebouncedSearchFieldState extends ConsumerState<_DebouncedSearchField> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;

  static const Duration _kDebounceDelay = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _ctrl.text = ref.read(clientsQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Si l'utilisateur a tout effacé, on propage instantanément (clear
    // visuel attendu, et la requête sans WHERE LIKE est gratuite).
    if (value.isEmpty) {
      ref.read(clientsQueryProvider.notifier).state = '';
      return;
    }
    _debounce = Timer(_kDebounceDelay, () {
      if (!mounted) return;
      ref.read(clientsQueryProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return TextField(
      controller: _ctrl,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: l10n.clientsListSearchHint,
      ),
      onChanged: _onChanged,
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

// (audit UI M4) `_Empty` interne supprimé au profit de `EmptyState`
// partagé sous `lib/widgets/empty_state.dart`.
