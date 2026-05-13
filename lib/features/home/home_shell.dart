import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/services/notification_service.dart' show NotificationStrings;
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
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  /// Cache des destinations de navigation, mémoizé par la `Locale`
  /// courante (audit v1.6.0 P4). Avant : le `List<AdaptiveDestination>`
  /// était reconstruit à chaque rebuild du shell — chaque changement
  /// d'onglet provoquait l'allocation de 6 objets `AdaptiveDestination`
  /// alors que rien n'avait changé. Maintenant : reconstruit seulement
  /// si la locale change.
  Locale? _destinationsLocale;
  List<AdaptiveDestination>? _destinationsCache;

  @override
  void initState() {
    super.initState();
    // Re-planifier les rappels du jour : c'est le seul endroit où l'on a à
    // la fois la base déverrouillée ET AppL10n.of(context). On le fait au
    // montage du shell (post-unlock) pour rattraper :
    //   - un reboot device (le boot receiver remet de vieilles alarms)
    //   - une restauration de sauvegarde (la base change sous la file)
    //   - un cold-start après que l'OS a tué l'app pendant un schedule
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final l10n = AppL10n.of(context);
      final strings = NotificationStrings.fromL10n(
        channelName: l10n.notifChannelName,
        channelDescription: l10n.notifChannelDescription,
        defaultTitle: l10n.notifDefaultTitle,
        body: l10n.notifBody,
        bodyWithLocation: l10n.notifBodyWithLocation,
      );
      try {
        // Source unique : NotificationReconciler enchaîne cancelAll +
        // re-schedule depuis la DB courante. Pas besoin pour HomeShell de
        // savoir que c'est un cancel-then-schedule sous le capot.
        await ref
            .read(notificationReconcilerProvider)
            .reconcile(strings: strings);
      } on Object {
        // best-effort : alarms manquées plutôt que crash
      }
      // v1.6.0 : sème les 6 templates par défaut au 1er unlock post-upgrade
      // (DB v6). Idempotent — si l'utilisateur a déjà supprimé un template
      // système, le seed ne le ressuscitera pas. `read` (pas `watch`) :
      // on n'a pas besoin d'écouter l'AsyncValue.
      try {
        await ref.read(reportTemplateSeedProvider.future);
      } on Object {
        // best-effort : pas critique au boot, l'utilisateur peut créer ses
        // propres canevas depuis Réglages si le seed échoue.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    // Gate sur databaseProvider résolu : avant ce refactor, tous les
    // repository providers faisaient `requireValue` au build, ce qui
    // throw `StateError` pendant la fenêtre [unlock OK → DB ouverte] et
    // affichait un flash d'ErrorView rouge. En attendant ici la résolution
    // du Future, les enfants du shell (et donc tous les `requireValue`
    // downstream) ne sont construits qu'une fois la DB prête.
    final dbAsync = ref.watch(databaseProvider);
    return dbAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              AppL10n.of(context).lockStorageError,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      data: (_) => _buildShell(context, ref),
    );
  }

  Widget _buildShell(BuildContext context, WidgetRef ref) {
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
    final destinations = _resolveDestinations(context, l10n);

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

  /// Reconstruit la liste des destinations seulement si la `Locale`
  /// effective a changé depuis le dernier build. Sinon retourne le cache
  /// — évite l'allocation de 6 `AdaptiveDestination` à chaque changement
  /// d'onglet (audit v1.6.0 P4).
  List<AdaptiveDestination> _resolveDestinations(
    BuildContext context,
    AppL10n l10n,
  ) {
    final locale = Localizations.localeOf(context);
    final cached = _destinationsCache;
    if (cached != null && _destinationsLocale == locale) {
      return cached;
    }
    final fresh = [
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
    _destinationsLocale = locale;
    _destinationsCache = fresh;
    return fresh;
  }
}
