import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../agenda/agenda_screen.dart';
import '../animals/animals_screen.dart';
import '../clients/clients_screen.dart';
import '../sessions/sessions_screen.dart';
import '../settings/settings_screen.dart';
import 'home_screen.dart';

/// Top-level navigation shell. Adapts to phone (bottom bar) and tablet
/// (navigation rail).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
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
      AdaptiveDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: l10n.navSettings,
      ),
    ];

    return AdaptiveScaffold(
      destinations: destinations,
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      title: Text(destinations[_index].label),
      body: IndexedStack(index: _index, children: pages),
    );
  }
}
