import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';

/// Auto-lock policy + timer driven by a [Stopwatch] (monotonic — immune to
/// clock-skew attacks where a rooted attacker could rewind the system clock
/// to keep the session alive).
///
/// Exposed as a [StateNotifier] so the Settings tile listens to the
/// configured [Duration] reactively: changing the value via
/// [setDurationMinutes] both persists it AND rebuilds anything that
/// `ref.watch`es the provider.
class AutoLockController extends StateNotifier<Duration> {
  AutoLockController(this._ref) : super(_defaultDuration) {
    _stopwatch.start();
  }

  static const _kDurationKey = 'auto_lock.minutes';
  static const Duration _defaultDuration = Duration(minutes: 5);

  final Ref _ref;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;

  /// Loads the user-configured duration from prefs (or falls back to 5 min).
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_kDurationKey);
    if (stored != null && stored > 0) {
      state = Duration(minutes: stored);
    }
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
  }

  /// Convenience getter for callers that don't want to watch the state.
  Duration get duration => state;

  Future<void> setDurationMinutes(int minutes) async {
    if (minutes < 1) return;
    state = Duration(minutes: minutes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDurationKey, minutes);
    onUserActivity();
  }

  /// Resets the inactivity stopwatch. Called on every pointer event AND on
  /// app resume. Throttled — pointer events fire at ~120 Hz during scroll,
  /// resetting the stopwatch every microsecond is wasteful (and creates
  /// pointless GC pressure). We only reset when at least 5 s have elapsed.
  void onUserActivity() {
    if (_stopwatch.elapsed.inSeconds < 5 && _stopwatch.isRunning) return;
    _stopwatch
      ..reset()
      ..start();
  }

  /// Forces a lock now (used when app goes to background).
  void lockNow() {
    _backgroundGrace?.cancel();
    _backgroundGrace = null;
    _ref.read(vaultSessionProvider.notifier).lock();
  }

  /// Schedule a lock after a short grace period. Used by the lifecycle
  /// listener: locking instantly on `onPause` / `onHide` would lock the
  /// vault every time the user opens a file picker, the share sheet, the
  /// biometric prompt, or pulls down the notification shade — yielding a
  /// terrible UX where most user actions force a re-unlock. With the grace
  /// period, those transient pauses are tolerated; only a true "user left
  /// the app" pause (longer than [_backgroundGracePeriod]) triggers a lock.
  void scheduleBackgroundLock() {
    _backgroundGrace?.cancel();
    _backgroundGrace = Timer(_backgroundGracePeriod, () {
      _backgroundGrace = null;
      if (_ref.read(vaultSessionProvider) != null) {
        _ref.read(vaultSessionProvider.notifier).lock();
      }
    });
  }

  /// Called when the app is back in the foreground — cancels any pending
  /// background lock and resets the inactivity timer.
  void cancelBackgroundLock() {
    _backgroundGrace?.cancel();
    _backgroundGrace = null;
    onUserActivity();
  }

  /// Grace period before locking on background. 2 minutes leaves ample
  /// room for file pickers / gallery navigation / share sheet / biometric
  /// prompt, and matches the user's expectation that briefly switching
  /// apps does not force a re-unlock. The real long-form auto-lock
  /// (configurable in Settings, default 5 min of *inactivity*) remains
  /// the authoritative session timeout — this constant only governs the
  /// transient pause/resume case.
  static const Duration _backgroundGracePeriod = Duration(minutes: 2);
  Timer? _backgroundGrace;

  void _tick() {
    if (_ref.read(vaultSessionProvider) == null) return; // already locked
    if (_stopwatch.elapsed >= state) {
      lockNow();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _backgroundGrace?.cancel();
    _backgroundGrace = null;
    _stopwatch.stop();
    super.dispose();
  }
}

final autoLockControllerProvider =
    StateNotifierProvider<AutoLockController, Duration>(AutoLockController.new);

/// Wraps the app with a [Listener] that records pointer events as activity
/// and an [AppLifecycleListener] that locks on background.
class AutoLockGuard extends ConsumerStatefulWidget {
  const AutoLockGuard({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AutoLockGuard> createState() => _AutoLockGuardState();
}

class _AutoLockGuardState extends ConsumerState<AutoLockGuard> {
  late final AppLifecycleListener _lifecycleListener;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      // **IMPORTANT — leçon v1.2.0 → v1.2.2** : Android fire `onHide`
      // chaque fois qu'une nouvelle activity prend l'écran, y compris
      // le **file picker** (DocumentsUI), le BiometricPrompt et le
      // share sheet. Si on locke immédiatement sur onHide, choisir une
      // photo provoque un écran noir au retour (vault locked → DB
      // fermée → ErrorView SizedBox.shrink dans le viewer). Donc :
      // onPause ET onHide passent tous deux par la grace de 2 min.
      // Seul onDetach (app vraiment tuée par l'OS) locke immédiatement.
      onPause: () => ref
          .read(autoLockControllerProvider.notifier)
          .scheduleBackgroundLock(),
      onHide: () => ref
          .read(autoLockControllerProvider.notifier)
          .scheduleBackgroundLock(),
      onDetach: () => ref.read(autoLockControllerProvider.notifier).lockNow(),
      onResume: () {
        ref.read(autoLockControllerProvider.notifier).cancelBackgroundLock();
        // L'utilisateur peut avoir modifié ses empreintes Android dans
        // les Réglages système pendant que l'app était en background.
        // On invalide le statut biométrique au retour pour que le
        // toggle Settings reflète la réalité (auto-cleanup côté provider
        // si enrolled && !available).
        ref.invalidate(biometricStatusProvider);
      },
    );
    Future<void>.microtask(() async {
      await ref.read(autoLockControllerProvider.notifier).init();
      // Reset the stopwatch the very first time we land in the guarded tree.
      // Without this, a stale stopwatch from a previous session could relock
      // the user immediately after unlock.
      ref.read(autoLockControllerProvider.notifier).onUserActivity();
      if (mounted) setState(() => _initialised = true);
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialised) {
      return const SizedBox.shrink();
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) =>
          ref.read(autoLockControllerProvider.notifier).onUserActivity(),
      onPointerMove: (_) =>
          ref.read(autoLockControllerProvider.notifier).onUserActivity(),
      child: widget.child,
    );
  }
}
