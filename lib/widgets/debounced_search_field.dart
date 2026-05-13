import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Barre de recherche débouncée réutilisable (audit perf H5).
///
/// Propage la valeur saisie au [stateProvider] passé en paramètre
/// **après** [debounce] (250 ms par défaut) sans relancer la requête
/// SQL sous-jacente à chaque keystroke. Le clear (champ vide) est
/// propagé instantanément pour un feedback visuel immédiat.
///
/// Utilisé par les listes clients et animaux ; aligne le pattern UX
/// entre les deux écrans (avant : clients débouncé, animaux non →
/// requêtes Drift à chaque caractère sur grand jeu).
class DebouncedSearchField extends ConsumerStatefulWidget {
  const DebouncedSearchField({
    super.key,
    required this.stateProvider,
    required this.hintText,
    this.debounce = const Duration(milliseconds: 250),
  });

  /// Provider d'état qui reçoit la valeur saisie (typiquement un
  /// `StateProvider<String>` exposé par la feature appelante).
  final StateProvider<String> stateProvider;

  /// Placeholder du `TextField`.
  final String hintText;

  /// Délai d'inactivité avant propagation. 250 ms est le sweet spot
  /// utilisateur (perceptible mais pas gênant) ; ne pas descendre sous
  /// 150 ms sinon le débounce devient invisible.
  final Duration debounce;

  @override
  ConsumerState<DebouncedSearchField> createState() =>
      _DebouncedSearchFieldState();
}

class _DebouncedSearchFieldState extends ConsumerState<DebouncedSearchField> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl.text = ref.read(widget.stateProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.isEmpty) {
      ref.read(widget.stateProvider.notifier).state = '';
      return;
    }
    _debounce = Timer(widget.debounce, () {
      if (!mounted) return;
      ref.read(widget.stateProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: widget.hintText,
      ),
      onChanged: _onChanged,
    );
  }
}
