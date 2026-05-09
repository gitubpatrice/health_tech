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
    return init.when(
      loading: () => const _Loading(),
      error: (e, _) => _Error(message: e.toString()),
      data: (initialised) =>
          initialised ? const _UnlockForm() : const _SetupForm(),
    );
  }
}

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

class _UnlockForm extends ConsumerStatefulWidget {
  const _UnlockForm();
  @override
  ConsumerState<_UnlockForm> createState() => _UnlockFormState();
}

class _UnlockFormState extends ConsumerState<_UnlockForm> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppL10n.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok =
        await ref.read(vaultSessionProvider.notifier).unlock(_ctrl.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = l10n.lockWrongPassphrase);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
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
                  Text(l10n.lockTitle,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(l10n.lockSubtitle),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _ctrl,
                    obscureText: true,
                    autofocus: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: l10n.lockPassphraseLabel,
                      errorText: _error,
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
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(l10n.lockUnlockButton),
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

class _SetupForm extends ConsumerStatefulWidget {
  const _SetupForm();
  @override
  ConsumerState<_SetupForm> createState() => _SetupFormState();
}

class _SetupFormState extends ConsumerState<_SetupForm> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppL10n.of(context);
    if (_passCtrl.text.length < 12) {
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
    await ref
        .read(vaultSessionProvider.notifier)
        .setupAndUnlock(_passCtrl.text);
    if (!mounted) return;
    ref.invalidate(vaultInitialisedProvider);
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
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
                  Text(l10n.lockSetupTitle,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(l10n.lockSetupSubtitle),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l10n.lockPassphraseLabel,
                      errorText: _error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l10n.lockSetupConfirmLabel,
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
                            child: CircularProgressIndicator(strokeWidth: 2))
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
