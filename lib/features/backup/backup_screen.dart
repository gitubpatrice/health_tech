import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../data/services/backup_service.dart';
import '../../l10n/generated/app_localizations.dart';

/// Settings → Backup. Two flows on one screen:
///   - **Export**: ask the user for a backup passphrase (≥12 chars), produce
///     the `.htbk` bundle, send it through the system share sheet so the
///     destination (mail / cloud / messaging) is the user's free choice.
///   - **Restore**: pick an `.htbk` file, ask for the passphrase, preview
///     manifest counts, confirm, then lock the vault and apply. After apply
///     the user re-unlocks with their **original vault passphrase** —
///     the backup passphrase only protects the file in transit.
class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupScreenTitle)),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _DisclaimerCard(text: l10n.backupExplainer),
          const SizedBox(height: 8),
          _ExportTile(),
          const Divider(height: 1),
          _RestoreTile(),
        ],
      ),
    );
  }
}

class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerHighest,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _ExportTile extends ConsumerWidget {
  Future<void> _run(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final passphrase = await _askPassphrase(
      context,
      title: l10n.backupExportPassphraseTitle,
      hint: l10n.backupExportPassphraseHint,
      confirm: true,
    );
    if (passphrase == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(l10n.backupExportInProgress),
      ),
    );

    try {
      final bytes = await ref
          .read(backupServiceProvider)
          .export(backupPassphrase: passphrase);
      final filename = _bundleFilename();
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: filename,
          mimeType: 'application/octet-stream',
        ),
      ]);
    } on ValidationError catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(_localiseError(l10n, e))));
    } on VaultLockedError {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.backupVaultMustBeUnlocked)),
      );
    }
  }

  String _bundleFilename() {
    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${pad(now.month)}${pad(now.day)}-${pad(now.hour)}${pad(now.minute)}';
    return 'health-tech-$stamp.htbk';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return ListTile(
      leading: const Icon(Icons.backup_outlined),
      title: Text(l10n.backupExportTitle),
      subtitle: Text(l10n.backupExportSubtitle),
      onTap: () => _run(context, ref),
    );
  }
}

class _RestoreTile extends ConsumerWidget {
  Future<void> _run(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !context.mounted) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;

    final passphrase = await _askPassphrase(
      context,
      title: l10n.backupRestorePassphraseTitle,
      hint: l10n.backupRestorePassphraseHint,
      confirm: false,
    );
    if (passphrase == null || !context.mounted) return;

    final service = ref.read(backupServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    BackupPreview preview;
    try {
      preview = await service.previewRestore(
        bundle: Uint8List.fromList(bytes),
        backupPassphrase: passphrase,
      );
    } on ValidationError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_localiseError(l10n, e))));
      return;
    }
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_outlined),
        title: Text(l10n.backupRestoreConfirmTitle),
        content: Text(
          l10n.backupRestoreConfirmBody(
            preview.attachmentCount,
            preview.headerCreatedAt ?? '?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l10n.backupRestoreConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Lock the vault BEFORE writing files: the open SQLCipher handle would
    // otherwise hold the .db file and corrupt mid-replace.
    ref.read(vaultSessionProvider.notifier).lock();
    try {
      await service.applyRestore(preview);
    } on Object catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      return;
    }
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.backupRestoreDone)));
    // Force the app back to the lock screen so providers re-init around
    // the restored DB & vault material.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return ListTile(
      leading: const Icon(Icons.restore_outlined),
      title: Text(l10n.backupRestoreTitle),
      subtitle: Text(l10n.backupRestoreSubtitle),
      onTap: () => _run(context, ref),
    );
  }
}

Future<String?> _askPassphrase(
  BuildContext context, {
  required String title,
  required String hint,
  required bool confirm,
}) async {
  final l10n = AppL10n.of(context);
  final ctrl = TextEditingController();
  final ctrlConfirm = TextEditingController();
  String? error;
  // Per-field visibility toggles, mirroring the lock screen UX so users
  // can verify what they typed before committing — critical with a
  // 12-character passphrase typed on a phone keyboard.
  var obscured = true;
  var obscuredConfirm = true;

  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          void submit() {
            final v = ctrl.text;
            if (v.length < 12) {
              setState(() => error = l10n.backupPassphraseTooShort);
              return;
            }
            if (confirm && v != ctrlConfirm.text) {
              setState(() => error = l10n.backupPassphraseMismatch);
              return;
            }
            Navigator.of(ctx).pop(v);
          }

          Widget visibility({
            required bool current,
            required VoidCallback onPressed,
          }) {
            return IconButton(
              icon: Icon(
                current
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              tooltip: current
                  ? l10n.lockShowPassphrase
                  : l10n.lockHidePassphrase,
              onPressed: onPressed,
            );
          }

          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(hint),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  obscureText: obscured,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.backupPassphraseLabel,
                    errorText: error,
                    suffixIcon: visibility(
                      current: obscured,
                      onPressed: () => setState(() => obscured = !obscured),
                    ),
                  ),
                ),
                if (confirm) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrlConfirm,
                    obscureText: obscuredConfirm,
                    decoration: InputDecoration(
                      labelText: l10n.backupPassphraseConfirmLabel,
                      suffixIcon: visibility(
                        current: obscuredConfirm,
                        onPressed: () =>
                            setState(() => obscuredConfirm = !obscuredConfirm),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.actionCancel),
              ),
              FilledButton(onPressed: submit, child: Text(l10n.actionContinue)),
            ],
          );
        },
      );
    },
  );
}

String _localiseError(AppL10n l10n, ValidationError e) {
  return switch (e.code) {
    'backup_passphrase_too_short' => l10n.backupPassphraseTooShort,
    'backup_wrong_passphrase' => l10n.backupRestoreWrongPassphrase,
    'backup_truncated' ||
    'backup_bad_magic' ||
    'backup_manifest_missing' ||
    'backup_vault_missing' => l10n.backupBundleInvalid,
    'backup_schema_unsupported' => l10n.backupSchemaUnsupported,
    _ => e.toString(),
  };
}
