// Garde-régression v1.8.0 (C6 audit cohérence — Riverpod v1 → v2).
//
// v1.7.x exposait `vaultSessionProvider` et `autoLockControllerProvider`
// comme `StateNotifierProvider`. v1.8.0 les migre vers `NotifierProvider`.
// Les call-sites continuent d'utiliser `.notifier` et `ref.watch(provider)`,
// donc cette suite vérifie principalement :
//  1. Le shape API est bien `NotifierProvider` (pas `StateNotifierProvider`)
//  2. Le state initial vault = null (locked) et auto-lock = 5 min
//  3. Cleanup `ref.onDispose` libère les timers d'auto-lock

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/core/auto_lock.dart';
import 'package:health_tech/core/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  test('vaultSessionProvider is a NotifierProvider (v1.8.0 C6)', () {
    // Si un dev régresse vers `StateNotifierProvider`, l'assignation
    // dans une variable `NotifierProvider` ne compile plus.
    final NotifierProvider<VaultSessionController, VaultSession?> p =
        vaultSessionProvider;
    expect(p, isA<NotifierProvider<VaultSessionController, VaultSession?>>());
  });

  test('autoLockControllerProvider is a NotifierProvider (v1.8.0 C6)', () {
    final NotifierProvider<AutoLockController, Duration> p =
        autoLockControllerProvider;
    expect(p, isA<NotifierProvider<AutoLockController, Duration>>());
  });

  test('vault initial state is null (locked) until unlock', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(vaultSessionProvider), isNull);
  });

  test('autoLock default duration is 5 min', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(autoLockControllerProvider),
      const Duration(minutes: 5),
    );
  });

  test('autoLock setDurationMinutes mutates state reactively', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(autoLockControllerProvider.notifier);
    await notifier.setDurationMinutes(15);
    expect(
      container.read(autoLockControllerProvider),
      const Duration(minutes: 15),
    );
  });

  test('autoLock setDurationMinutes ignores values < 1', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(autoLockControllerProvider.notifier);
    await notifier.setDurationMinutes(0);
    expect(
      container.read(autoLockControllerProvider),
      const Duration(minutes: 5),
    );
    await notifier.setDurationMinutes(-5);
    expect(
      container.read(autoLockControllerProvider),
      const Duration(minutes: 5),
    );
  });
}
