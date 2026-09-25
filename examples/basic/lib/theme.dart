import 'package:flutter/material.dart';

/// App theme, defined the way real apps tend to: a seed color, a custom font,
/// text theme tweaks and a few component themes, built by a helper.
class AppTheme {
  static const seed = Color(0xFF00696E);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colorScheme,
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(letterSpacing: 0.2),
      ),
      appBarTheme: const AppBarThemeData(centerTitle: true),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerHigh,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
