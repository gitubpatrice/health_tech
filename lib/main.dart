import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auto_lock.dart';
import 'core/providers.dart';
import 'core/theme.dart';
import 'features/home/home_shell.dart';
import 'features/lock/lock_screen.dart';
import 'l10n/generated/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
