import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

/// Modal shown before any sensitive data is captured. Returns true if the
/// user confirmed the disclaimer (i.e. they have informed the client).
class DisclaimerDialog {
  const DisclaimerDialog._();

  static Future<bool> show(BuildContext context) async {
    final l10n = AppL10n.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.health_and_safety_outlined, size: 32),
        title: Text(l10n.disclaimerHeadline),
        content: SingleChildScrollView(child: Text(l10n.disclaimerBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.disclaimerAccept),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }
}
