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
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          localiseError(context, error),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
