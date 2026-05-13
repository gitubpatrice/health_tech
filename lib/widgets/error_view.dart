import 'package:flutter/material.dart';

import '../core/errors.dart';
import '../l10n/generated/app_localizations.dart';

/// Renders a user-facing message for any caught error.
///
/// Maps [HealthError] subclasses to localised strings via their stable
/// `code`. Anything else (PlatformException, FormatException, ...) falls
/// back to a generic message — we explicitly DO NOT show `error.toString()`
/// to avoid leaking implementation details (Keystore status, file paths,
/// crypto error names) into the UI.
String localiseError(BuildContext context, Object error) {
  final l10n = AppL10n.of(context);
  if (error is HealthError) {
    switch (error.code) {
      case 'vault_locked':
        return l10n.errorVaultLocked;
      case 'vault_not_initialised':
        return l10n.errorVaultNotInitialised;
      case 'vault_already_initialised':
        return l10n.errorVaultAlreadyInitialised;
      case 'vault_wrong_passphrase':
        return l10n.errorVaultWrongPassphrase;
      case 'vault_locked_out':
        if (error is VaultLockedOutError) {
          return l10n.errorVaultLockedOut(error.remainingSeconds);
        }
        return l10n.errorGeneric;
      case 'client_consent_missing':
        return l10n.errorValidationConsent;
      case 'session_end_before_start':
        return l10n.errorValidationSessionEnd;
      case 'appointment_end_before_start':
        return l10n.errorValidationAppointmentEnd;
      case 'tag_label_empty':
        return l10n.errorValidationTagEmpty;
      case 'client_not_found':
        return l10n.errorValidationClientNotFound;
      default:
        return l10n.errorGeneric;
    }
  }
  return l10n.errorGeneric;
}

/// Centred error tile suitable for use in `AsyncValue.when(error: ...)`.
///
/// `VaultLockedError` is treated as a transient state, not a failure: when
/// the app pauses or the user manually locks, every stream that depends on
/// the vault throws this until `LockScreen` swaps in (a few frames later).
/// We render a blank space to avoid flashing a red "error" panel during
/// that handoff.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;

  /// Si fourni, affiche un bouton "Réessayer" sous le message. Idéal
  /// pour les `AsyncValue.when(error:)` reliés à un provider qu'on peut
  /// `ref.invalidate(...)` (audit UI H5).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error is VaultLockedError) return const SizedBox.shrink();
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(localiseError(context, error), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.actionRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
