import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/services/global_search_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../animals/animal_providers.dart';
import '../clients/client_providers.dart';
import '../home/home_shell.dart';
import '../sessions/session_providers.dart';

/// Single-screen global search reachable from the Home AppBar.
///
/// Debounce: 300 ms — fast enough to feel reactive, slow enough that a
/// 30-character query doesn't fire 30 SQL queries while the user types.
/// Encrypted notes are deliberately not searchable; the screen makes
/// that explicit via the helper text on the empty state.
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = const [];
  bool _busy = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(value));
  }

  Future<void> _run(String value) async {
    final query = value.trim();
    if (query == _lastQuery) return;
    _lastQuery = query;
    if (query.isEmpty) {
      setState(() => _hits = const []);
      return;
    }
    setState(() => _busy = true);
    try {
      final hits = await ref.read(globalSearchServiceProvider).search(query);
      if (!mounted || _lastQuery != query) return;
      setState(() => _hits = hits);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(SearchHit hit) {
    final tabNotifier = ref.read(homeTabProvider.notifier);
    switch (hit.kind) {
      case SearchHitKind.client:
        ref.read(selectedClientIdProvider.notifier).state = hit.id;
        tabNotifier.state = HomeTab.clients;
      case SearchHitKind.animal:
        ref.read(selectedAnimalIdProvider.notifier).state = hit.id;
        tabNotifier.state = HomeTab.animals;
      case SearchHitKind.session:
        ref.read(selectedSessionIdProvider.notifier).state = hit.id;
        tabNotifier.state = HomeTab.sessions;
      case SearchHitKind.appointment:
        tabNotifier.state = HomeTab.agenda;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.searchHint,
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: l10n.actionCancel,
              onPressed: () {
                _ctrl.clear();
                _run('');
              },
            ),
        ],
      ),
      body: _body(context, l10n),
    );
  }

  Widget _body(BuildContext context, AppL10n l10n) {
    if (_busy && _hits.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_lastQuery.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            l10n.searchEmptyHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    if (_hits.isEmpty) {
      return Center(child: Text(l10n.searchNoResults));
    }
    final grouped = _groupByKind(_hits);
    return ListView(
      children: [
        for (final entry in grouped.entries) ...[
          _SectionHeader(label: _kindLabel(l10n, entry.key)),
          for (final hit in entry.value)
            ListTile(
              leading: Icon(_kindIcon(hit.kind)),
              title: Text(hit.title),
              subtitle: hit.subtitle.isEmpty ? null : Text(hit.subtitle),
              onTap: () => _open(hit),
            ),
        ],
      ],
    );
  }

  static Map<SearchHitKind, List<SearchHit>> _groupByKind(
    List<SearchHit> hits,
  ) {
    final out = <SearchHitKind, List<SearchHit>>{};
    for (final h in hits) {
      out.putIfAbsent(h.kind, () => []).add(h);
    }
    return out;
  }

  static String _kindLabel(AppL10n l10n, SearchHitKind kind) {
    return switch (kind) {
      SearchHitKind.client => l10n.navClients,
      SearchHitKind.animal => l10n.navAnimals,
      SearchHitKind.session => l10n.navSessions,
      SearchHitKind.appointment => l10n.navAgenda,
    };
  }

  static IconData _kindIcon(SearchHitKind kind) {
    return switch (kind) {
      SearchHitKind.client => Icons.person_outline,
      SearchHitKind.animal => Icons.pets,
      SearchHitKind.session => Icons.event_note,
      SearchHitKind.appointment => Icons.event,
    };
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
