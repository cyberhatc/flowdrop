import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/storage/settings.dart';
import 'state/app_controller.dart';
import 'theme.dart';
import '../../features/shell/app_shell.dart';

/// Root widget. Theme is driven by persisted settings (dark by default,
/// system and light themes supported per spec §7).
class FlowDropApp extends ConsumerWidget {
  const FlowDropApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appControllerProvider.select((s) => s.settings));

    final brightness = switch (settings.themeMode) {
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.light => Brightness.light,
      AppThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    final theme = brightness == Brightness.dark
        ? FlowDropTheme.dark(settings.accent)
        : FlowDropTheme.light(settings.accent);

    return MaterialApp(
      title: AppLocalizations.of(context)?.appTitle ?? 'FlowDrop',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: FlowDropTheme.dark(settings.accent),
      themeMode: switch (settings.themeMode) {
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.system => ThemeMode.system,
      },
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AppShell(),
    );
  }
}
