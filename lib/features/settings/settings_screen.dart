import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auto_lock.dart';
import '../../core/providers.dart';
import '../../data/services/panic_service.dart';
import '../../data/vault/biometric_channel.dart' show BiometricFailure;
import '../../l10n/generated/app_localizations.dart';
import '../../utils/ephemeral_cache.dart';
import '../../widgets/error_view.dart' show localiseError;
import '../../widgets/snack_utils.dart';
import '../about/about_screen.dart';
import '../backup/backup_screen.dart';
import '../clients/client_providers.dart';
import '../legal/legal_screen.dart';
import '../templates/report_templates_screen.dart';

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
        const _StrictModeTile(),
        const Divider(height: 1),
        const _ExportClientTile(),
        const Divider(height: 1),
        const _PurgeClientTile(),
        const Divider(height: 1),
        const _PanicWipeTile(),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(l10n.settingsTemplatesTitle),
          subtitle: Text(l10n.settingsTemplatesSubtitle),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const ReportTemplatesScreen(),
            ),
          ),
        ),
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
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.settingsAboutTitle),
          subtitle: Text(l10n.settingsAboutSubtitle),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
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
    String? successMessage;
    String? errorMessage;
    try {
      if (turnOn) {
        await vault.enableBiometric(
          title: l10n.lockBiometricTitle,
          subtitle: l10n.settingsBiometricEnrollSubtitle,
          negativeButton: l10n.actionCancel,
        );
        successMessage = l10n.settingsBiometricEnabled;
      } else {
        await vault.disableBiometric();
        successMessage = l10n.settingsBiometricDisabled;
      }
    } on BiometricFailure catch (e) {
      // (v1.5.6) Discrimine annulation utilisateur (geste back / cancel)
      // d'un vrai échec hardware/crypto pour donner un feedback explicite.
      // Avant : tout passait dans le catch générique → message « erreur »
      // sans nuance, alors qu'une annulation volontaire n'en est pas une.
      if (e.userCancelled) {
        errorMessage = l10n.settingsBiometricEnableCanceled;
      } else if (e.keyInvalidated) {
        errorMessage = l10n.lockBiometricEnrollmentChanged;
      } else {
        errorMessage = l10n.settingsBiometricEnableFailed;
      }
    } on Object catch (e) {
      // Pas de e.toString() : on ne fuite pas les détails (Keystore status,
      // file paths, noms d'erreur crypto) à l'utilisateur. localiseError
      // tombe sur errorGeneric pour les types non-mappés.
      if (context.mounted) {
        errorMessage = localiseError(context, e);
      }
    }
    if (context.mounted) {
      final scheme = Theme.of(context).colorScheme;
      messenger.showSnackBar(
        buildFloatingSnack(
          successMessage ?? errorMessage ?? '',
          scheme,
          tone: errorMessage != null ? SnackTone.error : SnackTone.success,
        ),
      );
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

/// Toggle « Mode strict » : force la passphrase à chaque déverrouillage,
/// désactive la biométrie même dans la fenêtre courte. Pratiques sensibles.
class _StrictModeTile extends ConsumerStatefulWidget {
  const _StrictModeTile();

  @override
  ConsumerState<_StrictModeTile> createState() => _StrictModeTileState();
}

class _StrictModeTileState extends ConsumerState<_StrictModeTile> {
  bool? _value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _value = prefs.getBool(kStrictModePrefKey) ?? false);
  }

  Future<void> _toggle(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kStrictModePrefKey, v);
    if (!mounted) return;
    setState(() => _value = v);
    // Le LockScreen lit requirePassphraseProvider — on l'invalide pour
    // que la prochaine ouverture du Lock screen reflète immédiatement
    // le nouveau choix.
    ref.invalidate(requirePassphraseProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return SwitchListTile(
      secondary: const Icon(Icons.shield_outlined),
      title: Text(l10n.settingsStrictModeTitle),
      subtitle: Text(l10n.settingsStrictModeSubtitle),
      value: _value ?? false,
      onChanged: _value == null ? null : _toggle,
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
    final scheme = Theme.of(context).colorScheme;
    messenger.showSnackBar(
      buildFloatingSnack(
        '…',
        scheme,
        tone: SnackTone.info,
        duration: const Duration(seconds: 2),
      ),
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
    // Le ZIP RGPD contient des données santé en CLAIR (export Article 15).
    // share_plus matérialise dans cache/share_plus/ → on planifie une
    // purge 2 min plus tard pour limiter la fenêtre de fuite si l'app
    // cible (mail) ne consomme pas immédiatement.
    unawaited(EphemeralCache.scheduleSharePurge());
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

/// Panic-wipe : effacement total et irréversible de toute trace Health Tech
/// sur l'appareil. Pattern Files Tech aligné sur Pass / Notes / RFT / AI / PDF.
class _PanicWipeTile extends ConsumerWidget {
  const _PanicWipeTile();

  Future<void> _confirmAndWipe(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    // Double confirmation : on impose à l'utilisateur de TAPER le mot
    // EFFACER (localisé) pour valider. Évite un déclenchement par
    // double-tap accidentel ou enfant qui joue avec le téléphone.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          _PanicConfirmDialog(token: l10n.settingsPanicConfirmToken),
    );
    if (ok != true || !context.mounted) return;
    // v1.7.1 (M4 audit) — feedback haptique fort sur action irréversible.
    // `heavyImpact` est le pattern Files Tech pour panic / destruction
    // (aligné Pass Tech v2.4.4 U9, Notes Tech v1.1.0).
    unawaited(HapticFeedback.heavyImpact());
    final service = ref.read(panicServiceProvider);
    await service.wipe();
    // Le coffre est détruit → vault.lock() a déjà été invoqué par
    // destroy(). La session passe à null, le LockScreen reprend la
    // main et l'utilisateur tombe sur le setup vierge.
    await ref.read(vaultSessionProvider.notifier).lock();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.local_fire_department_outlined, color: cs.error),
      title: Text(l10n.settingsPanicTitle),
      subtitle: Text(l10n.settingsPanicSubtitle),
      onTap: () => _confirmAndWipe(context, ref),
    );
  }
}

class _PanicConfirmDialog extends StatefulWidget {
  const _PanicConfirmDialog({required this.token});
  final String token;
  @override
  State<_PanicConfirmDialog> createState() => _PanicConfirmDialogState();
}

class _PanicConfirmDialogState extends State<_PanicConfirmDialog> {
  late final TextEditingController _ctrl;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.local_fire_department_outlined, color: cs.error),
      title: Text(l10n.settingsPanicTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.settingsPanicWarning),
          const SizedBox(height: 16),
          Text(
            l10n.settingsPanicConfirmInstruction(widget.token),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: widget.token,
            ),
            onChanged: (v) =>
                setState(() => _ok = v.trim().toUpperCase() == widget.token),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _ok ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(backgroundColor: cs.error),
          child: Text(l10n.settingsPanicConfirmAction),
        ),
      ],
    );
  }
}
