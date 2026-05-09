import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';

/// Auto-lock policy + timer driven by a [Stopwatch] (monotonic — immune to
/// clock-skew attacks where a rooted attacker could rewind the system clock
/// to keep the session alive).
class AutoLockController {
  AutoLockController(this._ref) {
    _stopwatch.start();
  }

  static const _kDurationKey = 'auto_lock.minutes';
  static const Duration _defaultDuration = Duration(minutes: 5);

  final Ref _ref;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  Duration _allowed = _defaultDuration;

  /// Loads the user-configured duration from prefs (or falls back to 5 min).
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_kDurationKey);
    if (stored != null && stored > 0) {
      _allowed = Duration(minutes: stored);
    }
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
  }

  Duration get duration => _allowed;

  Future<void> setDurationMinutes(int minutes) async {
    if (minutes < 1) return;
    _allowed = Duration(minutes: minutes);
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
    _ref.read(vaultSessionProvider.notifier).lock();
  }

  void _tick() {
    if (_ref.read(vaultSessionProvider) == null) return; // already locked
    if (_stopwatch.elapsed >= _allowed) {
      lockNow();
    }
  }

  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _stopwatch.stop();
  }
}

final autoLockControllerProvider = Provider<AutoLockController>((ref) {
  final controller = AutoLockController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

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
      onPause: () => ref.read(autoLockControllerProvider).lockNow(),
      onHide: () => ref.read(autoLockControllerProvider).lockNow(),
      onDetach: () => ref.read(autoLockControllerProvider).lockNow(),
      onResume: () => ref.read(autoLockControllerProvider).onUserActivity(),
    );
    Future<void>.microtask(() async {
      await ref.read(autoLockControllerProvider).init();
      // Reset the stopwatch the very first time we land in the guarded tree.
      // Without this, a stale stopwatch from a previous session could relock
      // the user immediately after unlock.
      ref.read(autoLockControllerProvider).onUserActivity();
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
          ref.read(autoLockControllerProvider).onUserActivity(),
      onPointerMove: (_) =>
          ref.read(autoLockControllerProvider).onUserActivity(),
      child: widget.child,
    );
  }
}
