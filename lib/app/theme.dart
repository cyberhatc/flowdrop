import 'package:flutter/material.dart';

import '../core/storage/settings.dart';

/// Neon-glow design system.
///
/// The palette is intentionally dark-first: deep ink backgrounds with a single
/// saturated accent and a soft companion glow.
class FlowDropTheme {
  static const Color ink = Color(0xFF04060C);
  static const Color inkRaised = Color(0xFF0A1020);
  static const Color panel = Color(0xFF0D1426);
  static const Color mist = Color(0xFF8FA3C8);

  static Color accent(AccentColor value) {
    switch (value) {
      case AccentColor.cyan:
        return const Color(0xFF4DE1FF);
      case AccentColor.violet:
        return const Color(0xFFA379FF);
      case AccentColor.magenta:
        return const Color(0xFFFF5CCB);
      case AccentColor.lime:
        return const Color(0xFF9BFF7A);
    }
  }

  static Color companion(AccentColor value) {
    switch (value) {
      case AccentColor.cyan:
        return const Color(0xFFA379FF);
      case AccentColor.violet:
        return const Color(0xFFFF5CCB);
      case AccentColor.magenta:
        return const Color(0xFF4DE1FF);
      case AccentColor.lime:
        return const Color(0xFF4DE1FF);
    }
  }

  static ThemeData dark(AccentColor accentColor) =>
      _build(Brightness.dark, accentColor);

  static ThemeData light(AccentColor accentColor) =>
      _build(Brightness.light, accentColor);

  static ThemeData _build(Brightness brightness, AccentColor accentValue) {
    final primary = brightness == Brightness.dark
        ? accent(accentValue)
        : Color.lerp(accent(accentValue), Colors.black, 0.35)!;
    final secondary = brightness == Brightness.dark
        ? companion(accentValue)
        : Color.lerp(companion(accentValue), Colors.black, 0.25)!;
    final isDark = brightness == Brightness.dark;

    final background = isDark ? ink : const Color(0xFFF3F6FF);
    final surface = isDark ? panel : Colors.white;
    final onSurface = isDark
        ? const Color(0xFFE9F0FF)
        : const Color(0xFF101828);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: isDark ? ink : Colors.white,
      secondary: secondary,
      onSecondary: isDark ? ink : Colors.white,
      error: const Color(0xFFFF6B81),
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? inkRaised : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? inkRaised : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.45)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.0),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: onSurface.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary.withValues(alpha: 0.35)
              : null,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: onSurface,
        displayColor: onSurface,
      ),
      dividerColor: onSurface.withValues(alpha: 0.08),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? const Color(0xFF16203A)
            : const Color(0xFF1B2436),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? inkRaised.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.95),
        indicatorColor: primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}
