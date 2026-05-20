import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../data/services/backup_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/ephemeral_cache.dart';
import '../../widgets/error_view.dart' show localiseError;
import '../../widgets/snack_utils.dart';

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

    // (audit sécu M5) Avertissement si la passphrase de backup est la
    // même que celle du coffre. Réutilisation ⇒ un attaquant qui acquiert
    // le `.htbk` n'a plus qu'un seul Argon2id à casser au lieu de deux.
    // L'utilisateur peut choisir de continuer (cas légitime : terrain
    // pro avec un manager qui les voit comme un seul secret), mais il
    // est informé.
    final samePassphrase = await ref
        .read(vaultProvider)
        .matchesUnlockedPassphrase(passphrase);
    if (!context.mounted) return;
    if (samePassphrase) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            icon: Icon(Icons.warning_amber_outlined, color: cs.error),
            title: Text(l10n.backupSamePassphraseTitle),
            content: Text(l10n.backupSamePassphraseBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.actionCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.backupSamePassphraseContinue),
              ),
            ],
          );
        },
      );
      if (proceed != true || !context.mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    messenger.showSnackBar(
      buildFloatingSnack(
        l10n.backupExportInProgress,
        scheme,
        tone: SnackTone.info,
        duration: const Duration(seconds: 2),
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
      // Le bundle .htbk est chiffré, mais share_plus le matérialise sur
      // disque dans cache/share_plus/. On planifie une purge 2 minutes
      // plus tard — l'app cible (Drive / Mail) a eu le temps de
      // consommer, et le fichier ne traîne pas indéfiniment dans le
      // cache OS jusqu'à éviction LRU.
      unawaited(EphemeralCache.scheduleSharePurge());
    } on ValidationError catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        buildFloatingSnack(
          _localiseError(l10n, e),
          scheme,
          tone: SnackTone.error,
        ),
      );
    } on VaultLockedError {
      if (!context.mounted) return;
      messenger.showSnackBar(
        buildFloatingSnack(
          l10n.backupVaultMustBeUnlocked,
          scheme,
          tone: SnackTone.error,
        ),
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
    if (picked == null || picked.files.isEmpty || !context.mounted) {
      // Purge le file_picker cache même en cas d'annulation, pour pas
      // laisser un .htbk traîner si l'utilisateur a sélectionné puis
      // changé d'avis dans le dialog de confirmation.
      unawaited(EphemeralCache.purgeFilePicker());
      return;
    }
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      unawaited(EphemeralCache.purgeFilePicker());
      return;
    }

    final passphrase = await _askPassphrase(
      context,
      title: l10n.backupRestorePassphraseTitle,
      hint: l10n.backupRestorePassphraseHint,
      confirm: false,
    );
    if (passphrase == null || !context.mounted) return;

    final service = ref.read(backupServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    BackupPreview preview;
    try {
      preview = await service.previewRestore(
        bundle: Uint8List.fromList(bytes),
        backupPassphrase: passphrase,
      );
    } on ValidationError catch (e) {
      messenger.showSnackBar(
        buildFloatingSnack(
          _localiseError(l10n, e),
          scheme,
          tone: SnackTone.error,
        ),
      );
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
    // otherwise hold the .db file and corrupt mid-replace. lock() est
    // asynchrone et await la fermeture effective du DB.
    await ref.read(vaultSessionProvider.notifier).lock();
    try {
      await service.applyRestore(preview);
    } on Object catch (e) {
      // Quel que soit le résultat (succès ou erreur), on purge le
      // file_picker cache pour ne pas laisser le .htbk d'origine
      // dormir dans cache/file_picker/ post-restore.
      unawaited(EphemeralCache.purgeFilePicker());
      // Audit M13 : wipe les bytes clairs détenus par BackupPreview.
      preview.wipe();
      if (!context.mounted) return;
      // Évite la fuite via e.toString() (chemins de fichiers, codes
      // Keystore, noms d'erreurs crypto) — localiseError → errorGeneric
      // pour tout ce qui n'est pas un HealthError mappé.
      messenger.showSnackBar(
        buildFloatingSnack(
          localiseError(context, e),
          scheme,
          tone: SnackTone.error,
        ),
      );
      return;
    }
    unawaited(EphemeralCache.purgeFilePicker());
    preview.wipe();
    if (!context.mounted) return;
    messenger.showSnackBar(
      buildFloatingSnack(
        l10n.backupRestoreDone,
        scheme,
        tone: SnackTone.success,
      ),
    );
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
}) {
  // (audit H1) StatefulWidget plutôt que `StatefulBuilder + closures`,
  // pour disposer proprement les deux TextEditingController quand le
  // dialog se ferme — sinon export/restore répétés fuitent un controller
  // à chaque ouverture.
  return showDialog<String>(
    context: context,
    builder: (ctx) =>
        _PassphraseDialog(title: title, hint: hint, confirm: confirm),
  );
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({
    required this.title,
    required this.hint,
    required this.confirm,
  });
  final String title;
  final String hint;
  final bool confirm;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final TextEditingController _ctrl = TextEditingController();
  final TextEditingController _ctrlConfirm = TextEditingController();
  String? _error;
  // Per-field visibility toggles, mirroring the lock screen UX so users
  // can verify what they typed before committing — critical with a
  // 14-character passphrase typed on a phone keyboard.
  bool _obscured = true;
  bool _obscuredConfirm = true;

  @override
  void dispose() {
    _ctrl.dispose();
    _ctrlConfirm.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppL10n.of(context);
    final v = _ctrl.text;
    if (v.length < 14) {
      setState(() => _error = l10n.backupPassphraseTooShort);
      return;
    }
    if (widget.confirm && v != _ctrlConfirm.text) {
      setState(() => _error = l10n.backupPassphraseMismatch);
      return;
    }
    Navigator.of(context).pop(v);
  }

  Widget _visibilityIcon({
    required bool current,
    required VoidCallback onPressed,
  }) {
    final l10n = AppL10n.of(context);
    return IconButton(
      icon: Icon(
        current ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
      tooltip: current ? l10n.lockShowPassphrase : l10n.lockHidePassphrase,
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.hint),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            obscureText: _obscured,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.backupPassphraseLabel,
              errorText: _error,
              suffixIcon: _visibilityIcon(
                current: _obscured,
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
            ),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _ctrlConfirm,
              obscureText: _obscuredConfirm,
              decoration: InputDecoration(
                labelText: l10n.backupPassphraseConfirmLabel,
                suffixIcon: _visibilityIcon(
                  current: _obscuredConfirm,
                  onPressed: () =>
                      setState(() => _obscuredConfirm = !_obscuredConfirm),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.actionContinue)),
      ],
    );
  }
}

String _localiseError(AppL10n l10n, ValidationError e) {
  return switch (e.code) {
    'backup_passphrase_too_short' => l10n.backupPassphraseTooShort,
    'backup_wrong_passphrase' => l10n.backupRestoreWrongPassphrase,
    'backup_truncated' ||
    'backup_bad_magic' ||
    'backup_manifest_missing' ||
    'backup_vault_missing' => l10n.backupBundleInvalid,
    'backup_schema_unsupported' ||
    'backup_db_version_too_new' => l10n.backupSchemaUnsupported,
    'backup_kdf_params_too_weak' ||
    'backup_incomplete' => l10n.backupBundleInvalid,
    _ => l10n.errorGeneric,
  };
}
