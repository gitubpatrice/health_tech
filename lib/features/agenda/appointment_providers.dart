import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/appointment.dart';

/// Upcoming appointments stream pour l'onglet **Agenda**.
///
/// Distinct du `upcomingAppointmentsProvider` du dashboard (Home), qui
/// est plafonné à 5 items pour le résumé d'accueil. Ici on garde la
/// borne par défaut du repo (50) pour alimenter la liste complète.
/// Deux providers homonymes coexistaient avant — Riverpod en faisait
/// deux subscriptions Drift distinctes sur la même requête (audit H4).
final agendaUpcomingProvider = StreamProvider<List<Appointment>>((ref) {
  return ref.watch(appointmentRepositoryProvider).watchUpcoming();
});

typedef _Range = ({DateTime from, DateTime to});

final appointmentsRangeProvider =
    StreamProvider.family<List<Appointment>, _Range>((ref, range) {
      return ref
          .watch(appointmentRepositoryProvider)
          .watchInRange(range.from, range.to);
    });
