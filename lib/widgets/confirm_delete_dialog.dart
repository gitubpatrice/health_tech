import 'package:flutter/material.dart';

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
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
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
