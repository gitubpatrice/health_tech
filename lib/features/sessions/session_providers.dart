import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/session.dart';

/// Live list of recent sessions (descending by start date). Repository streams
/// auto-refresh on insert/update.
final sessionsStreamProvider = StreamProvider<List<Session>>((ref) {
  final repo = ref.watch(sessionRepositoryProvider);
  // Default range: last 12 months to next 6 months — enough for the list view.
  final now = DateTime.now();
  return repo.watchInRange(
    now.subtract(const Duration(days: 365)),
    now.add(const Duration(days: 180)),
  );
});

final selectedSessionIdProvider = StateProvider<String?>((_) => null);

final selectedSessionProvider = FutureProvider<Session?>((ref) async {
  final id = ref.watch(selectedSessionIdProvider);
  if (id == null) return null;
  return ref.watch(sessionRepositoryProvider).getById(id);
});

final sessionsByClientProvider = StreamProvider.family<List<Session>, String>((
  ref,
  clientId,
) {
  return ref.watch(sessionRepositoryProvider).watchByClient(clientId);
});

final sessionsByAnimalProvider = StreamProvider.family<List<Session>, String>((
  ref,
  animalId,
) {
  return ref.watch(sessionRepositoryProvider).watchByAnimal(animalId);
});
