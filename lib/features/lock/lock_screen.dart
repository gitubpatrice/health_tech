import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// Single entry-point: shows either setup (first launch) or unlock.
/// Routes to home on success.
class LockScreen extends ConsumerWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final init = ref.watch(vaultInitialisedProvider);
    final l10n = AppL10n.of(context);
    return init.when(
      loading: () => const _Loading(),
      // The lock screen is reached BEFORE auth, so any raw exception text
      // is exposed to a hostile observer. Show a generic, localised message
      // and rely on logs / crash reporting for the underlying detail.
      error: (e, _) => _Error(message: l10n.lockStorageError),
      data: (initialised) =>
          initialised ? const _UnlockForm() : const _SetupForm(),
    );
  }
}

/// Minimum passphrase length enforced at setup. 12 chars is enough for
/// a passphrase made of distinct words; passwords made of a single word
/// + numbers will still be weak — the UI nudges users towards length.
const int kMinPassphraseLength = 12;

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _Error extends StatelessWidget {
  const _Error({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(message)));
}

/// Suffix icon that toggles a bound `obscureText` flag. Reused across the
/// 3 passphrase fields so they all expose the same interaction.
class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({
    required this.obscured,
    required this.onPressed,
    required this.l10n,
  });

  final bool obscured;
  final VoidCallback onPressed;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
      tooltip: obscured ? l10n.lockShowPassphrase : l10n.lockHidePassphrase,
      onPressed: onPressed,
    );
  }
}

class _UnlockForm extends ConsumerStatefulWidget {
  const _UnlockForm();
  @override
  ConsumerState<_UnlockForm> createState() => _UnlockFormState();
}

class _UnlockFormState extends ConsumerState<_UnlockForm> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  bool _obscured = true;
  String? _error;
  bool _biometricAttempted = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    if (_biometricAttempted || _busy) return;
    _biometricAttempted = true;
    final status = await ref.read(biometricStatusProvider.future);
    if (!status.readyForUnlock || !mounted) return;
    final l10n = AppL10n.of(context);
    setState(() => _busy = true);
    try {
      final ok = await ref
          .read(vaultSessionProvider.notifier)
          .unlockWithBiometric(
            title: l10n.lockBiometricTitle,
            subtitle: l10n.lockBiometricSubtitle,
            negativeButton: l10n.lockBiometricFallback,
          );
      if (mounted && !ok) {
        setState(() => _error = l10n.lockBiometricFailed);
      }
    } on Object {
      // User cancelled or hardware rejected — fall back silently to passphrase.
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _submit() async {
    final l10n = AppL10n.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final passphrase = _ctrl.text;
    final ok = await ref.read(vaultSessionProvider.notifier).unlock(passphrase);
    // Best-effort: blank the controller as soon as possible. This won't
    // wipe the underlying Dart String (immutable, GC-eligible only) but
    // releases the controller-held reference so the next GC can reclaim it.
    _ctrl.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = l10n.lockWrongPassphrase);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final bioStatus = ref.watch(biometricStatusProvider);
    // Auto-prompt on first build when biometric is enrolled. The prompt
    // appears immediately so the user does not have to tap a separate
    // button — passphrase remains available behind it.
    bioStatus.whenData((s) {
      if (s.readyForUnlock && !_biometricAttempted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
      }
    });
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.lockTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.lockSubtitle),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _ctrl,
                    obscureText: _obscured,
                    autofocus: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: l10n.lockPassphraseLabel,
                      errorText: _error,
                      suffixIcon: _VisibilityToggle(
                        obscured: _obscured,
                        onPressed: () => setState(() => _obscured = !_obscured),
                        l10n: l10n,
                      ),
                    ),
                    onSubmitted: _busy ? null : (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.lockUnlockButton),
                  ),
                  if (bioStatus.valueOrNull?.readyForUnlock ?? false) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () {
                              _biometricAttempted = false;
                              _tryBiometric();
                            },
                      icon: const Icon(Icons.fingerprint),
                      label: Text(l10n.lockBiometricButton),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupForm extends ConsumerStatefulWidget {
  const _SetupForm();
  @override
  ConsumerState<_SetupForm> createState() => _SetupFormState();
}

class _SetupFormState extends ConsumerState<_SetupForm> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  bool _passObscured = true;
  bool _confirmObscured = true;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppL10n.of(context);
    if (_passCtrl.text.length < kMinPassphraseLength) {
      setState(() => _error = l10n.lockSetupTooShort);
      return;
    }
    if (_passCtrl.text != _confirmCtrl.text) {
      setState(() => _error = l10n.lockSetupMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final passphrase = _passCtrl.text;
    await ref.read(vaultSessionProvider.notifier).setupAndUnlock(passphrase);
    _passCtrl.clear();
    _confirmCtrl.clear();
    if (!mounted) return;
    ref.invalidate(vaultInitialisedProvider);
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final lengthHint = l10n.lockSetupMinLength(kMinPassphraseLength);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.lockSetupTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.lockSetupSubtitle),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _passObscured,
                    decoration: InputDecoration(
                      labelText: l10n.lockPassphraseLabel,
                      helperText: lengthHint,
                      errorText: _error,
                      suffixIcon: _VisibilityToggle(
                        obscured: _passObscured,
                        onPressed: () =>
                            setState(() => _passObscured = !_passObscured),
                        l10n: l10n,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: _confirmObscured,
                    decoration: InputDecoration(
                      labelText: l10n.lockSetupConfirmLabel,
                      suffixIcon: _VisibilityToggle(
                        obscured: _confirmObscured,
                        onPressed: () => setState(
                          () => _confirmObscured = !_confirmObscured,
                        ),
                        l10n: l10n,
                      ),
                    ),
                    onSubmitted: _busy ? null : (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.lockSetupCreateButton),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
