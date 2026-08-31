import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Palette tuned for a darkened wheelhouse: near-black backgrounds so the
/// screen does not wash out night vision, and only two saturated accents so the
/// two talk directions stay distinguishable at a glance.
abstract final class NightPalette {
  static const Color background = Color(0xFF05070C);
  static const Color surface = Color(0xFF0C1219);
  static const Color surfaceRaised = Color(0xFF141D28);
  static const Color outline = Color(0xFF223040);

  static const Color textPrimary = Color(0xFFE9EFF7);
  static const Color textSecondary = Color(0xFF93A3B8);
  static const Color textMuted = Color(0xFF5C6B7F);

  /// English side (crew speaking English).
  static const Color english = Color(0xFF3DA9FC);

  /// Chinese side (crew speaking Mandarin).
  static const Color chinese = Color(0xFFFFB020);

  static const Color online = Color(0xFF35D07F);
  static const Color danger = Color(0xFFFF5F63);
}

abstract final class NightTheme {
  static const SystemUiOverlayStyle overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: NightPalette.background,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData build() {
    const colorScheme = ColorScheme.dark(
      primary: NightPalette.english,
      onPrimary: Color(0xFF041220),
      secondary: NightPalette.chinese,
      onSecondary: Color(0xFF1A1200),
      surface: NightPalette.surface,
      onSurface: NightPalette.textPrimary,
      surfaceContainerHighest: NightPalette.surfaceRaised,
      onSurfaceVariant: NightPalette.textSecondary,
      outline: NightPalette.outline,
      error: NightPalette.danger,
      onError: Color(0xFF2A0508),
    );

    final base = ThemeData(
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      useMaterial3: true,
    );

    return base.copyWith(
      scaffoldBackgroundColor: NightPalette.background,
      splashFactory: NoSplash.splashFactory,
      textTheme: base.textTheme.apply(
        bodyColor: NightPalette.textPrimary,
        displayColor: NightPalette.textPrimary,
      ),
      dividerTheme: const DividerThemeData(
        color: NightPalette.outline,
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: NightPalette.surfaceRaised,
        contentTextStyle: TextStyle(color: NightPalette.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
