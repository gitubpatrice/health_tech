import 'package:flutter/material.dart';

import 'error_view.dart';

/// Encapsule le pattern récurrent dans les form save handlers :
///   1. setState busy=true
///   2. await action
///   3. catch any error → snack localisé (sans fuite e.toString())
///   4. finally setState busy=false (si encore monté)
///
/// Évite l'oubli classique de `if (!mounted) return;` après l'await ET
/// la duplication ~12× du même squelette try/finally dans clients/
/// animals/sessions/appointments form screens.
///
/// Usage typique :
/// ```dart
/// await runWithBusy(
///   context: context,
///   setBusy: (v) => setState(() => _busy = v),
///   action: () async {
///     final saved = await repo.create(draft);
///     if (mounted) Navigator.of(context).pop(true);
///   },
/// );
/// ```
Future<void> runWithBusy({
  required BuildContext context,
  required void Function(bool) setBusy,
  required Future<void> Function() action,
}) async {
  setBusy(true);
  try {
    await action();
  } on Object catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  } finally {
    if (context.mounted) setBusy(false);
  }
}

/// Affiche une SnackBar avec le message localisé pour [error]. Toute
/// erreur non-mappée tombe sur `errorGeneric` plutôt que d'exposer
/// `e.toString()` (chemin de fichier, code Keystore, nom de classe
/// d'exception interne).
void showErrorSnack(BuildContext context, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(localiseError(context, error))));
}
