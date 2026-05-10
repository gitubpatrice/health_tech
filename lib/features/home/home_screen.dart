import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/appointment.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/date_format.dart';
import '../../widgets/breakpoints.dart';
import '../../widgets/disclaimer_dialog.dart';
import '../sessions/session_form_screen.dart';
import 'home_shell.dart';
import 'home_stats_providers.dart';

/// Dashboard with large, legible icon shortcuts (the user-facing default
/// "front door" for the app).
///
/// Layout follows the same Files Tech UX language as Notes Tech / Pass Tech:
/// - 2 columns on phone portrait
/// - 3 columns on phone landscape / small tablet
/// - 4 columns on tablet expanded
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    void goTo(HomeTab tab) => ref.read(homeTabProvider.notifier).state = tab;
    final shortcuts = <_HomeShortcut>[
      _HomeShortcut(
        icon: Icons.person_outline,
        label: l10n.navClients,
        color: scheme.primaryContainer,
        onTap: () => goTo(HomeTab.clients),
      ),
      _HomeShortcut(
        icon: Icons.pets,
        label: l10n.navAnimals,
        color: scheme.secondaryContainer,
        onTap: () => goTo(HomeTab.animals),
      ),
      _HomeShortcut(
        icon: Icons.event_note,
        label: l10n.homeQuickSession,
        color: scheme.tertiaryContainer,
        onTap: () => _newSession(context),
      ),
      _HomeShortcut(
        icon: Icons.event,
        label: l10n.navAgenda,
        color: scheme.surfaceContainerHigh,
        onTap: () => goTo(HomeTab.agenda),
      ),
    ];

    final cols = switch (context.windowSize) {
      WindowSize.compact => 2,
      WindowSize.medium => 3,
      WindowSize.expanded => 4,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.count(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.1,
            children: [for (final s in shortcuts) _ShortcutCard(s)],
          ),
          const SizedBox(height: 24),
          const _StatsRow(),
          const SizedBox(height: 24),
          Text(
            l10n.homeTodayAppointments,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const _TodayAppointments(),
          const SizedBox(height: 24),
          Text(
            l10n.homeUpcoming,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const _UpcomingAppointments(),
        ],
      ),
    );
  }
}

class _StatsRow extends ConsumerWidget {
  const _StatsRow();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final stats = ref.watch(homeStatsProvider);
    return stats.when(
      loading: () => const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (s) => Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.event_note,
              value: s.sessionsThisMonth.toString(),
              label: l10n.homeStatsSessionsMonth,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              icon: Icons.people_outline,
              value: s.distinctClientsThisMonth.toString(),
              label: l10n.homeStatsClientsMonth,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              icon: Icons.person_outline,
              value: s.totalClients.toString(),
              label: l10n.homeStatsClientsTotal,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHigh,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayAppointments extends ConsumerWidget {
  const _TodayAppointments();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final stats = ref.watch(homeStatsProvider);
    return stats.maybeWhen(
      data: (s) => s.appointmentsToday.isEmpty
          ? _EmptyCard(text: l10n.homeNoAppointmentsToday)
          : _AppointmentList(items: s.appointmentsToday, showDate: false),
      orElse: () => _EmptyCard(text: l10n.homeNoAppointmentsToday),
    );
  }
}

class _UpcomingAppointments extends ConsumerWidget {
  const _UpcomingAppointments();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final stats = ref.watch(homeStatsProvider);
    return stats.maybeWhen(
      data: (s) => s.upcomingAppointments.isEmpty
          ? _EmptyCard(text: l10n.homeNoUpcoming)
          : _AppointmentList(items: s.upcomingAppointments, showDate: true),
      orElse: () => _EmptyCard(text: l10n.homeNoUpcoming),
    );
  }
}

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({required this.items, required this.showDate});
  final List<Appointment> items;
  final bool showDate;
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.event),
              title: Text(items[i].title ?? '—'),
              subtitle: Text(
                showDate
                    ? '${formatDate(items[i].startAt)} · '
                          '${formatTime(items[i].startAt)}'
                    : formatTime(items[i].startAt),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ),
    );
  }
}

Future<void> _newSession(BuildContext context) async {
  // Sessions touch sensitive health data, so the disclaimer is shown here
  // even though the form itself is a "create only" path (consents on the
  // client are mandatory before the session can persist).
  final accepted = await DisclaimerDialog.show(context);
  if (!accepted || !context.mounted) return;
  await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => const SessionFormScreen(),
      fullscreenDialog: true,
    ),
  );
}

class _HomeShortcut {
  const _HomeShortcut({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard(this.shortcut);
  final _HomeShortcut shortcut;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: shortcut.color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: shortcut.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(shortcut.icon, size: 48),
              const SizedBox(height: 12),
              Text(
                shortcut.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
