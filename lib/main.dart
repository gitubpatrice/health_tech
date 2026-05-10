import 'dart:io';

import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

import 'core/auto_lock.dart';
import 'core/providers.dart';
import 'core/theme.dart';
import 'features/home/home_shell.dart';
import 'features/lock/lock_screen.dart';
import 'l10n/generated/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Route AES-GCM and Argon2id to the platform's native crypto provider
  // (BoringSSL via JNI on Android) instead of the pure-Dart fallback.
  // The package now auto-registers via the Flutter plugin discovery
  // mechanism — the import alone is what wires it. We keep the explicit
  // call (deprecated but harmless) for the next reader's sake: it makes
  // the dependency on native crypto visible at the entry point.
  // ignore: deprecated_member_use
  FlutterCryptography.enable();
  // Redirect package:sqlite3 (used by Drift) to the SQLCipher .so bundled
  // with sqlcipher_flutter_libs. NOTE: this only sets the override on the
  // main isolate — the actual database opens in a worker isolate spawned
  // by NativeDatabase.createInBackground, which re-applies the override
  // through `isolateSetup` (see HealthDb.open).
  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  }
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const ProviderScope(child: HealthApp()));
}

class HealthApp extends ConsumerWidget {
  const HealthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(vaultSessionProvider);
    return MaterialApp(
      onGenerateTitle: (ctx) => AppL10n.of(ctx).appTitle,
      theme: HealthTheme.light(),
      darkTheme: HealthTheme.dark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fr'), Locale('en')],
      home: session == null
          ? const LockScreen()
          : const AutoLockGuard(child: HomeShell()),
      debugShowCheckedModeBanner: false,
    );
  }
}
