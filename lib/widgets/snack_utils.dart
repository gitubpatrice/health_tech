import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'error_view.dart';

/// Tonalité d'une [SnackBar] (audit UI H4) — unifie le rendu floating
/// entre toutes les apps Files Tech (`showFloatingSnack`).
enum SnackTone { info, success, error }

/// Affiche une [SnackBar] floating au style cohérent (couleurs issues
/// de [ColorScheme], jamais hardcoded). Centralise le pattern précédemment
/// dupliqué dans une quarantaine de handlers.
void showFloatingSnack(
  BuildContext context,
  String message, {
  SnackTone tone = SnackTone.info,
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,
}) {
  final scheme = Theme.of(context).colorScheme;
  final (bg, fg) = switch (tone) {
    SnackTone.error => (scheme.errorContainer, scheme.onErrorContainer),
    SnackTone.success => (
      scheme.secondaryContainer,
      scheme.onSecondaryContainer,
    ),
    SnackTone.info => (scheme.inverseSurface, scheme.onInverseSurface),
  };
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: TextStyle(color: fg)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: bg,
      duration: duration,
      action: action,
    ),
  );
}

/// Variante "erreur" qui s'appuie sur [localiseError] pour produire un
/// message safe (jamais d'`e.toString()` brut). Aligne le pattern existant
/// dans `busy_helpers.showErrorSnack` avec l'esthétique floating.
void showLocalisedErrorSnack(BuildContext context, Object error) {
  showFloatingSnack(
    context,
    localiseError(context, error),
    tone: SnackTone.error,
  );
}

/// Helper pour les snacks de succès simples ("Enregistré").
void showSuccessSnack(BuildContext context, String message) {
  showFloatingSnack(context, message, tone: SnackTone.success);
}

/// Décline le message standard "Réessayer" depuis l'l10n — évite de
/// hardcoder le label dans chaque call site.
SnackBarAction retryAction(BuildContext context, VoidCallback onRetry) {
  return SnackBarAction(
    label: AppL10n.of(context).actionRetry,
    onPressed: onRetry,
  );
}

/// v1.7.2 (M5/C1 audit cohérence) — variante "builder" qui retourne juste
/// le [SnackBar] sans l'afficher. Utile pour les call sites async qui
/// **doivent** capturer le [ScaffoldMessengerState] + [ColorScheme] AVANT
/// le premier `await` (pattern `use_build_context_synchronously`) puis
/// appeler `messenger.showSnackBar(buildFloatingSnack(...))` après le gap.
///
/// Évite la duplication du switch tone côté call site.
SnackBar buildFloatingSnack(
  String message,
  ColorScheme scheme, {
  SnackTone tone = SnackTone.info,
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,
}) {
  final (bg, fg) = switch (tone) {
    SnackTone.error => (scheme.errorContainer, scheme.onErrorContainer),
    SnackTone.success => (
      scheme.secondaryContainer,
      scheme.onSecondaryContainer,
    ),
    SnackTone.info => (scheme.inverseSurface, scheme.onInverseSurface),
  };
  return SnackBar(
    content: Text(message, style: TextStyle(color: fg)),
    behavior: SnackBarBehavior.floating,
    backgroundColor: bg,
    duration: duration,
    action: action,
  );
}
