import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/auto_lock.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../backup/backup_screen.dart';
import '../clients/client_providers.dart';
import '../legal/legal_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        const _AutoLockTile(),
        const Divider(height: 1),
        const _BiometricTile(),
        const Divider(height: 1),
        const _ExportClientTile(),
        const Divider(height: 1),
        const _PurgeClientTile(),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: Text(l10n.settingsBackupTitle),
          subtitle: Text(l10n.settingsBackupSubtitle),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: Text(l10n.settingsLegalTitle),
          subtitle: Text(l10n.settingsLegalSubtitle),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const LegalScreen()),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(l10n.lockTitle),
          onTap: () => ref.read(vaultSessionProvider.notifier).lock(),
        ),
      ],
    );
  }
}

class _AutoLockTile extends ConsumerWidget {
  const _AutoLockTile();

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in const [1, 2, 5, 10, 15, 30, 60])
                ListTile(
                  title: Text(l10n.settingsAutoLockMinutes(m)),
                  onTap: () => Navigator.of(ctx).pop(m),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      await ref
          .read(autoLockControllerProvider.notifier)
          .setDurationMinutes(picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    // Watch the Duration so the trailing label refreshes as soon as the
    // user picks a new value — previously the controller was a plain
    // class and the change was invisible (the tile still showed the
    // initial 5 min, even though the actual lock interval had changed).
    final duration = ref.watch(autoLockControllerProvider);
    return ListTile(
      leading: const Icon(Icons.timer_outlined),
      title: Text(l10n.settingsAutoLockTitle),
      subtitle: Text(l10n.settingsAutoLockSubtitle),
      trailing: Text(l10n.settingsAutoLockMinutes(duration.inMinutes)),
      onTap: () => _pick(context, ref),
    );
  }
}

class _BiometricTile extends ConsumerWidget {
  const _BiometricTile();

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool turnOn) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final vault = ref.read(vaultProvider);
    try {
      if (turnOn) {
        await vault.enableBiometric(
          title: l10n.lockBiometricTitle,
          subtitle: l10n.settingsBiometricEnrollSubtitle,
          negativeButton: l10n.actionCancel,
        );
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsBiometricEnabled)),
        );
      } else {
        await vault.disableBiometric();
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsBiometricDisabled)),
        );
      }
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
    ref.invalidate(biometricStatusProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final status = ref.watch(biometricStatusProvider);
    return status.when(
      loading: () => const ListTile(
        leading: Icon(Icons.fingerprint),
        title: SizedBox(
          height: 24,
          child: Center(child: LinearProgressIndicator()),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (s) => SwitchListTile(
        secondary: const Icon(Icons.fingerprint),
        title: Text(l10n.settingsBiometricTitle),
        subtitle: Text(
          s.available
              ? l10n.settingsBiometricSubtitle
              : l10n.settingsBiometricUnavailable,
        ),
        value: s.enrolled,
        onChanged: s.available ? (v) => _toggle(context, ref, v) : null,
      ),
    );
  }
}

class _ExportClientTile extends ConsumerWidget {
  const _ExportClientTile();

  Future<void> _pickAndExport(BuildContext context, WidgetRef ref) async {
    final list = await ref.read(clientsStreamProvider.future);
    if (list.isEmpty || !context.mounted) return;
    final l10n = AppL10n.of(context);
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.settingsRgpdExportTitle),
        children: [
          for (final c in list)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(c.id),
              child: Text(c.fullName),
            ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(duration: Duration(seconds: 2), content: Text('…')),
    );
    final bytes = await ref
        .read(rgpdExportServiceProvider)
        .exportClient(selected);
    final client = list.firstWhere((c) => c.id == selected);
    final safeName = client.fullName
        .replaceAll(RegExp('[^A-Za-z0-9_-]'), '-')
        .replaceAll(RegExp('-+'), '-');
    await Share.shareXFiles([
      XFile.fromData(
        bytes,
        name: 'health-tech-rgpd-$safeName.zip',
        mimeType: 'application/zip',
      ),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return ListTile(
      leading: const Icon(Icons.download_outlined),
      title: Text(l10n.settingsRgpdExportTitle),
      subtitle: Text(l10n.settingsRgpdExportSubtitle),
      onTap: () => _pickAndExport(context, ref),
    );
  }
}

class _PurgeClientTile extends ConsumerWidget {
  const _PurgeClientTile();

  Future<void> _pickAndPurge(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final list = await ref.read(clientsStreamProvider.future);
    if (list.isEmpty || !context.mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.settingsRgpdPurgeTitle),
        children: [
          for (final c in list)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(c.id),
              child: Text(c.fullName),
            ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_outlined),
        title: Text(l10n.settingsRgpdPurgeTitle),
        content: Text(l10n.settingsRgpdPurgeSubtitle),
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
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(purgeServiceProvider).purgeClient(selected);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return ListTile(
      leading: Icon(
        Icons.delete_forever_outlined,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(l10n.settingsRgpdPurgeTitle),
      subtitle: Text(l10n.settingsRgpdPurgeSubtitle),
      onTap: () => _pickAndPurge(context, ref),
    );
  }
}
