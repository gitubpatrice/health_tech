import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/animal.dart';
import '../../domain/tag.dart';

final animalsQueryProvider = StateProvider<String>((_) => '');
final animalsSpeciesFilterProvider = StateProvider<String?>((_) => null);

/// Tag filter (AND across the selected tag ids). Empty = no filtering.
final animalsTagFilterProvider = StateProvider<Set<String>>(
  (_) => <String>{},
);

final animalsStreamProvider = StreamProvider<List<Animal>>((ref) {
  final query = ref.watch(animalsQueryProvider);
  final species = ref.watch(animalsSpeciesFilterProvider);
  final tagIds = ref.watch(animalsTagFilterProvider);
  final repo = ref.watch(animalRepositoryProvider);
  final tagRepo = ref.watch(tagRepositoryProvider);

  return repo
      .watchAll(query: query, speciesFilter: species)
      .asyncMap((animals) async {
    if (tagIds.isEmpty) return animals;
    final allowed = await tagRepo.ownerIdsTaggedWithAll(
      ownerType: TagOwner.animal,
      tagIds: tagIds.toList(),
    );
    if (allowed == null) return animals;
    return animals.where((a) => allowed.contains(a.id)).toList();
  });
});

final selectedAnimalIdProvider = StateProvider<String?>((_) => null);

final selectedAnimalProvider = FutureProvider<Animal?>((ref) async {
  final id = ref.watch(selectedAnimalIdProvider);
  if (id == null) return null;
  return ref.watch(animalRepositoryProvider).getById(id);
});

/// Live list of animals attached to a given client (used inside the client
/// detail screen).
final animalsByClientProvider =
    StreamProvider.family<List<Animal>, String>((ref, clientId) {
  final repo = ref.watch(animalRepositoryProvider);
  return repo.watchByClient(clientId);
});
