import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../l10n/generated/app_localizations.dart';

/// Generic confirmation dialog used by every detail screen for soft-delete.
/// Returns `true` if the user confirmed.
///
/// Centralises the 3 copies that lived inside client/animal/session detail
/// (and that previously displayed the wrong entity label because they all
/// shared client-only l10n keys).
Future<bool> showConfirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final l10n = AppL10n.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          // v1.7.1 (M1 audit) — `autofocus: true` sur Cancel : pattern
          // Files Tech pour tout dialog destructif (anti-clic réflexe sur
          // Supprimer). Aligné Pass Tech v2.4.4 U2 / Notes Tech v1.1.0 F1 /
          // PDF Tech v1.12.5 U3 / RFT v2.13.2 S3.
          autofocus: true,
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () {
            // v1.7.1 (M4 audit) — feedback haptique sur action destructive.
            // `mediumImpact` est le pattern Files Tech pour delete (Pass Tech
            // v2.4.4, Notes Tech v1.1.0 F4). Le `heavyImpact` est réservé au
            // panic-wipe (irréversibilité globale).
            HapticFeedback.mediumImpact();
            Navigator.of(ctx).pop(true);
          },
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          child: Text(l10n.actionDelete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
