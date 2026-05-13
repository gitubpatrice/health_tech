import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/session.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/date_format.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/breakpoints.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import 'session_detail_screen.dart';
import 'session_form_screen.dart';
import 'session_l10n.dart';
import 'session_providers.dart';

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Stack(
      children: [
        MasterDetailLayout(
          list: _SessionsList(),
          detail: SessionDetailScreen(),
        ),
        Positioned(right: 16, bottom: 16, child: _AddSessionFab()),
      ],
    );
  }
}

class _AddSessionFab extends ConsumerWidget {
  const _AddSessionFab();

  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const SessionFormScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return FloatingActionButton.extended(
      onPressed: () => _open(context),
      icon: const Icon(Icons.event_note),
      label: Text(l10n.actionAdd),
    );
  }
}

class _SessionsList extends ConsumerWidget {
  const _SessionsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final list = ref.watch(sessionsStreamProvider);
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e),
      data: (sessions) => sessions.isEmpty
          ? EmptyState(
              icon: Icons.event_note_outlined,
              title: l10n.sessionsListEmpty,
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: sessions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _SessionTile(session: sessions[i]),
            ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session});
  final Session session;

  Future<void> _select(BuildContext context, WidgetRef ref) async {
    ref.read(selectedSessionIdProvider.notifier).state = session.id;
    if (context.isCompact) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const SessionDetailScreen()),
      );
    }
  }

  Color _statusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (session.status) {
      SessionStatus.done => scheme.tertiary,
      SessionStatus.cancelled => scheme.error,
      SessionStatus.noShow => scheme.error,
      SessionStatus.confirmed => scheme.primary,
      _ => scheme.outline,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final selectedId = ref.watch(selectedSessionIdProvider);
    return ListTile(
      selected: selectedId == session.id,
      leading: CircleAvatar(
        backgroundColor: _statusColor(context).withValues(alpha: 0.15),
        child: Icon(Icons.event_note, color: _statusColor(context)),
      ),
      title: Text(
        '${formatDayMonth(session.startAt)} · ${formatTime(session.startAt)}',
      ),
      subtitle: Text(
        '${kindLabel(l10n, session.kind)} · '
        '${statusLabel(l10n, session.status)}',
      ),
      onTap: () => _select(context, ref),
    );
  }
}
