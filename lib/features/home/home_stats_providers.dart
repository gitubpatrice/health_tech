import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/appointment.dart';
import '../../domain/client.dart';
import '../../domain/session.dart';

/// Aggregated metrics shown on the Home dashboard. Streams live off the
/// existing repositories' Drift queries, so any insert / update / delete
/// triggers an automatic refresh — no manual invalidation needed.
/// Entrée unifiée pour les listes « Aujourd'hui » et « Prochains » sur
/// le dashboard : indistingue le RDV pur (table `appointments`) de la
/// séance planifiée future (table `sessions`). Les deux ont un créneau
/// horaire et un statut — c'est tout ce dont la home a besoin pour
/// rendre une ligne. Le tap pourra par la suite ouvrir l'écran détail
/// approprié selon [kind].
class UpcomingEntry {
  const UpcomingEntry({
    required this.id,
    required this.startAt,
    required this.title,
    required this.kind,
  });

  /// Le UUID — sessionId ou appointmentId. Utilisé comme clé stable et
  /// pour la future navigation au tap.
  final String id;
  final DateTime startAt;

  /// Libellé court (titre du RDV ou kind de la séance).
  final String title;

  /// Source d'origine : `'appointment'` (RDV pur) ou `'session'` (séance
  /// planifiée future). Permet d'afficher une icône différente et de
  /// router le tap vers le bon écran de détail.
  final String kind;

  static const String kindAppointment = 'appointment';
  static const String kindSession = 'session';
}

class HomeStats {
  const HomeStats({
    required this.totalClients,
    required this.sessionsThisMonth,
    required this.distinctClientsThisMonth,
    required this.entriesToday,
    required this.upcomingEntries,
  });

  final int totalClients;
  final int sessionsThisMonth;

  /// Unique client IDs seen this month — useful for "clients vus ce mois-ci".
  final int distinctClientsThisMonth;

  /// RDV + séances planifiées dont le créneau tombe dans la journée
  /// locale courante, fusionnés et triés par heure de début.
  final List<UpcomingEntry> entriesToday;

  /// RDV + séances planifiées futures (> aujourd'hui), fusionnés, triés
  /// ascendant, plafonnés à 5. Les séances « done / cancelled / no_show »
  /// sont exclues par construction côté repo.
  final List<UpcomingEntry> upcomingEntries;
}

/// `now` "réactif" — re-fire chaque jour à minuit local pour que les
/// providers qui dépendent de "aujourd'hui" basculent au lendemain sans
/// nécessiter un rebuild manuel. Avant, `appointmentsTodayProvider`
/// capturait `DateTime.now()` au build du provider et restait bloqué
/// sur la date initiale jusqu'à un cold-start.
final _todayBoundaryProvider = StreamProvider<DateTime>((ref) async* {
  while (true) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    yield today;
    final nextMidnight = today.add(const Duration(days: 1, seconds: 1));
    await Future<void>.delayed(nextMidnight.difference(DateTime.now()));
  }
});

/// Today's appointments, recomputed on every DB change. Bounds use local
/// midnight-to-midnight so a session starting at 23h45 stays in "today".
final appointmentsTodayProvider = StreamProvider<List<Appointment>>((ref) {
  final repo = ref.watch(appointmentRepositoryProvider);
  final today = ref.watch(_todayBoundaryProvider).valueOrNull;
  if (today == null) return const Stream.empty();
  final end = today.add(const Duration(days: 1));
  return repo.watchInRange(today, end);
});

/// Sessions in the calendar month containing `now`. Bornes recalculées via
/// `_todayBoundaryProvider` qui re-fire à minuit, donc le mois bascule
/// automatiquement le 1er du mois suivant.
final sessionsThisMonthProvider = StreamProvider<List<Session>>((ref) {
  final repo = ref.watch(sessionRepositoryProvider);
  final today = ref.watch(_todayBoundaryProvider).valueOrNull;
  if (today == null) return const Stream.empty();
  final start = DateTime(today.year, today.month, 1);
  final end = DateTime(today.year, today.month + 1, 1);
  return repo.watchInRange(start, end);
});

/// Up to 5 next appointments after now.
final upcomingAppointmentsProvider = StreamProvider<List<Appointment>>((ref) {
  final repo = ref.watch(appointmentRepositoryProvider);
  return repo.watchUpcoming(limit: 5);
});

/// Séances futures planifiées (status planned / confirmed) — utilisé pour
/// que la home affiche aussi les séances créées via le quick-shortcut
/// « Nouvelle séance » et planifiées pour le futur.
final upcomingSessionsProvider = StreamProvider<List<Session>>((ref) {
  final repo = ref.watch(sessionRepositoryProvider);
  return repo.watchUpcoming(limit: 10);
});

/// Séances d'aujourd'hui (toutes statuts, pour pouvoir aussi cocher les
/// séances `done` du jour côté UI dashboard).
final sessionsTodayProvider = StreamProvider<List<Session>>((ref) {
  final repo = ref.watch(sessionRepositoryProvider);
  final today = ref.watch(_todayBoundaryProvider).valueOrNull;
  if (today == null) return const Stream.empty();
  final end = today.add(const Duration(days: 1));
  return repo.watchInRange(today, end);
});

/// Live client list (for the total count). Decoupled from search-filtered
/// `clientsStreamProvider` so the count is unaffected by the user typing
/// in the clients tab search field.
final allClientsProvider = StreamProvider<List<Client>>((ref) {
  return ref.watch(clientRepositoryProvider).watchAll();
});

/// Combines the live streams above into a single typed snapshot for the
/// dashboard. Each source is observed as an `AsyncValue`; the combined
/// state is loading until all four have produced their first value.
final homeStatsProvider = Provider<AsyncValue<HomeStats>>((ref) {
  final appsToday = ref.watch(appointmentsTodayProvider);
  final appsUpcoming = ref.watch(upcomingAppointmentsProvider);
  final sessionsToday = ref.watch(sessionsTodayProvider);
  final sessionsUpcoming = ref.watch(upcomingSessionsProvider);
  final monthSessionsAv = ref.watch(sessionsThisMonthProvider);
  final clients = ref.watch(allClientsProvider);

  final all = <AsyncValue<Object>>[
    appsToday,
    appsUpcoming,
    sessionsToday,
    sessionsUpcoming,
    monthSessionsAv,
    clients,
  ];
  if (all.any((a) => a.isLoading)) return const AsyncValue.loading();
  for (final a in all) {
    final err = a.error;
    if (err != null) return AsyncValue.error(err, StackTrace.current);
  }

  final monthSessions = monthSessionsAv.requireValue;
  final now = DateTime.now();

  // Fusion appointment + session pour les listes home. Les séances `done`
  // de la journée restent visibles côté « Aujourd'hui » (la praticienne
  // veut voir ce qu'elle a fait dans la journée même si c'est cloturé),
  // mais pas côté « Prochains » (filtre status au repo).
  final entriesTodayBuilder = <UpcomingEntry>[
    for (final a in appsToday.requireValue)
      UpcomingEntry(
        id: a.id,
        startAt: a.startAt,
        title: (a.title?.trim().isNotEmpty ?? false)
            ? a.title!.trim()
            : a.kind ?? '—',
        kind: UpcomingEntry.kindAppointment,
      ),
    for (final s in sessionsToday.requireValue)
      UpcomingEntry(
        id: s.id,
        startAt: s.startAt,
        title: s.kind,
        kind: UpcomingEntry.kindSession,
      ),
  ]..sort((a, b) => a.startAt.compareTo(b.startAt));

  final upcomingBuilder = <UpcomingEntry>[
    for (final a in appsUpcoming.requireValue)
      UpcomingEntry(
        id: a.id,
        startAt: a.startAt,
        title: (a.title?.trim().isNotEmpty ?? false)
            ? a.title!.trim()
            : a.kind ?? '—',
        kind: UpcomingEntry.kindAppointment,
      ),
    for (final s in sessionsUpcoming.requireValue)
      // Une séance peut tomber aujourd'hui ET être future (créée à
      // l'instant pour ce soir). On dédupe côté « Prochains » en gardant
      // strictement les créneaux postérieurs à minuit demain — sinon le
      // même item apparaîtrait dans « Aujourd'hui » ET dans « Prochains ».
      if (s.startAt.isAfter(DateTime(now.year, now.month, now.day, 23, 59, 59)))
        UpcomingEntry(
          id: s.id,
          startAt: s.startAt,
          title: s.kind,
          kind: UpcomingEntry.kindSession,
        ),
  ]..sort((a, b) => a.startAt.compareTo(b.startAt));

  return AsyncValue.data(
    HomeStats(
      totalClients: clients.requireValue.length,
      sessionsThisMonth: monthSessions.length,
      distinctClientsThisMonth: monthSessions
          .map((s) => s.clientId)
          .toSet()
          .length,
      entriesToday: entriesTodayBuilder,
      upcomingEntries: upcomingBuilder.take(5).toList(growable: false),
    ),
  );
});
