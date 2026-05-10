import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/appointment.dart';

/// Upcoming appointments stream (used by Home dashboard + Agenda upcoming).
final upcomingAppointmentsProvider = StreamProvider<List<Appointment>>((ref) {
  return ref.watch(appointmentRepositoryProvider).watchUpcoming();
});

typedef _Range = ({DateTime from, DateTime to});

final appointmentsRangeProvider =
    StreamProvider.family<List<Appointment>, _Range>((ref, range) {
      return ref
          .watch(appointmentRepositoryProvider)
          .watchInRange(range.from, range.to);
    });
