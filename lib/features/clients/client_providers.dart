import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/client.dart';
import '../../domain/tag.dart';

/// Free-text query bound to the search bar above the clients list.
final clientsQueryProvider = StateProvider<String>((_) => '');

/// Tag IDs that the user wants to filter by (AND across selected tags).
/// Empty set means no filtering.
final clientsTagFilterProvider = StateProvider<Set<String>>(
  (_) => <String>{},
);

/// Live list of clients filtered by free-text [clientsQueryProvider] AND
/// (optionally) by [clientsTagFilterProvider].
///
/// We layer the tag filter on top of the SQL stream rather than joining at
/// the SQL level: tag links can change without invalidating the underlying
/// clients stream, and the tag filter is small (a Set lookup).
final clientsStreamProvider = StreamProvider<List<Client>>((ref) {
  final query = ref.watch(clientsQueryProvider);
  final tagIds = ref.watch(clientsTagFilterProvider);
  final repo = ref.watch(clientRepositoryProvider);
  final tagRepo = ref.watch(tagRepositoryProvider);

  return repo.watchAll(query: query).asyncMap((clients) async {
    if (tagIds.isEmpty) return clients;
    final allowed = await tagRepo.ownerIdsTaggedWithAll(
      ownerType: TagOwner.client,
      tagIds: tagIds.toList(),
    );
    if (allowed == null) return clients;
    return clients.where((c) => allowed.contains(c.id)).toList();
  });
});

/// Currently selected client id (used by the master-detail layout). Null when
/// nothing is selected.
final selectedClientIdProvider = StateProvider<String?>((_) => null);

/// Resolves the selected client (with decrypted sensitive fields) on demand.
final selectedClientProvider = FutureProvider<Client?>((ref) async {
  final id = ref.watch(selectedClientIdProvider);
  if (id == null) return null;
  final repo = ref.watch(clientRepositoryProvider);
  return repo.getById(id);
});
