import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../widgets/breakpoints.dart';
import '../../widgets/disclaimer_dialog.dart';
import '../animals/animal_form_screen.dart';
import '../clients/client_form_screen.dart';
import '../sessions/session_form_screen.dart';

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
    final shortcuts = <_HomeShortcut>[
      _HomeShortcut(
        icon: Icons.person_add_alt,
        label: l10n.navClients,
        color: scheme.primaryContainer,
        onTap: () => _addClient(context),
      ),
      _HomeShortcut(
        icon: Icons.pets,
        label: l10n.navAnimals,
        color: scheme.secondaryContainer,
        onTap: () => _addAnimal(context),
      ),
      _HomeShortcut(
        icon: Icons.event_note,
        label: l10n.homeQuickSession,
        color: scheme.tertiaryContainer,
        onTap: () => _addSession(context),
      ),
      _HomeShortcut(
        icon: Icons.event,
        label: l10n.navAgenda,
        color: scheme.surfaceContainerHigh,
        onTap: () {
          /* agenda v0.4 */
        },
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
          Text(
            l10n.homeTodayAppointments,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          // TODO replace with real list bound to providers
          const _EmptyState(),
        ],
      ),
    );
  }
}

Future<void> _addClient(BuildContext context) async {
  final accepted = await DisclaimerDialog.show(context);
  if (!accepted || !context.mounted) return;
  await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => const ClientFormScreen(),
      fullscreenDialog: true,
    ),
  );
}

Future<void> _addAnimal(BuildContext context) async {
  await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => const AnimalFormScreen(),
      fullscreenDialog: true,
    ),
  );
}

Future<void> _addSession(BuildContext context) async {
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('—', style: Theme.of(context).textTheme.bodyLarge),
        ),
      ),
    );
  }
}
