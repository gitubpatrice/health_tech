import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/appointment.dart';
import '../../domain/client.dart';
import '../../domain/session.dart';

/// Aggregated metrics shown on the Home dashboard. Streams live off the
/// existing repositories' Drift queries, so any insert / update / delete
/// triggers an automatic refresh — no manual invalidation needed.
class HomeStats {
  const HomeStats({
    required this.totalClients,
    required this.sessionsThisMonth,
    required this.distinctClientsThisMonth,
    required this.appointmentsToday,
    required this.upcomingAppointments,
  });

  final int totalClients;
  final int sessionsThisMonth;

  /// Unique client IDs seen this month — useful for "clients vus ce mois-ci".
  final int distinctClientsThisMonth;

  /// Appointments whose start time falls inside today's local-day window,
  /// already sorted by start time ascending.
  final List<Appointment> appointmentsToday;

  /// Future appointments (>= now), sorted ascending, capped at 5.
  final List<Appointment> upcomingAppointments;
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
  final today = ref.watch(appointmentsTodayProvider);
  final upcoming = ref.watch(upcomingAppointmentsProvider);
  final sessions = ref.watch(sessionsThisMonthProvider);
  final clients = ref.watch(allClientsProvider);

  if (today.isLoading ||
      upcoming.isLoading ||
      sessions.isLoading ||
      clients.isLoading) {
    return const AsyncValue.loading();
  }
  final error =
      today.error ?? upcoming.error ?? sessions.error ?? clients.error;
  if (error != null) {
    return AsyncValue.error(error, StackTrace.current);
  }

  final monthSessions = sessions.requireValue;
  return AsyncValue.data(
    HomeStats(
      totalClients: clients.requireValue.length,
      sessionsThisMonth: monthSessions.length,
      distinctClientsThisMonth: monthSessions
          .map((s) => s.clientId)
          .toSet()
          .length,
      appointmentsToday: today.requireValue,
      upcomingAppointments: upcoming.requireValue,
    ),
  );
});
