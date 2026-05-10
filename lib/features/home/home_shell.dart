import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../agenda/agenda_screen.dart';
import '../animals/animals_screen.dart';
import '../clients/clients_screen.dart';
import '../search/global_search_screen.dart';
import '../sessions/sessions_screen.dart';
import '../settings/settings_screen.dart';
import 'home_screen.dart';

/// Bottom-nav / navigation-rail destination.
///
/// Order matches the order in `HomeShell.destinations` / `HomeShell.pages`
/// and is the only source of truth for the index — no magic numbers.
enum HomeTab { home, clients, animals, sessions, agenda, settings }

/// Currently selected destination. Lives at the top so home shortcut
/// cards can switch tabs without callback plumbing, and so the system
/// back button can return us to Home instead of leaving the app and
/// forcing the user to re-enter their passphrase.
final homeTabProvider = StateProvider<HomeTab>((_) => HomeTab.home);

/// Top-level navigation shell. Adapts to phone (bottom bar) and tablet
/// (navigation rail).
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final index = ref.watch(homeTabProvider);
    const pages = [
      HomeScreen(),
      ClientsScreen(),
      AnimalsScreen(),
      SessionsScreen(),
      AgendaScreen(),
      SettingsScreen(),
    ];
    final destinations = [
      AdaptiveDestination(
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        label: l10n.navHome,
      ),
      AdaptiveDestination(
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: l10n.navClients,
      ),
      AdaptiveDestination(
        icon: Icons.pets_outlined,
        selectedIcon: Icons.pets,
        label: l10n.navAnimals,
      ),
      AdaptiveDestination(
        icon: Icons.event_note_outlined,
        selectedIcon: Icons.event_note,
        label: l10n.navSessions,
      ),
      AdaptiveDestination(
        icon: Icons.calendar_today_outlined,
        selectedIcon: Icons.calendar_today,
        label: l10n.navAgenda,
      ),
      // Settings: gear icon only, no label — keeps the bottom bar
      // legible with 6 destinations on a phone.
      const AdaptiveDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: '',
      ),
    ];

    return PopScope(
      canPop: index == HomeTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // System back outside Home → go back to Home rather than leave the
        // app (which would force the user to re-unlock with their
        // passphrase). Only the Home tab itself lets the back gesture
        // close the app normally.
        ref.read(homeTabProvider.notifier).state = HomeTab.home;
      },
      child: AdaptiveScaffold(
        destinations: destinations,
        selectedIndex: index.index,
        onDestinationSelected: (i) =>
            ref.read(homeTabProvider.notifier).state = HomeTab.values[i],
        title: Text(
          // Fall back to the settings label when the destination has none
          // (settings is icon-only in the bottom bar but still deserves a
          // proper page title).
          destinations[index.index].label.isEmpty
              ? l10n.navSettings
              : destinations[index.index].label,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: l10n.searchTitle,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const GlobalSearchScreen(),
                fullscreenDialog: true,
              ),
            ),
          ),
        ],
        body: IndexedStack(index: index.index, children: pages),
      ),
    );
  }
}
