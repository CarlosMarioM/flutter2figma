import 'package:flutter/material.dart';

abstract final class ShowcaseTheme {
  static const seed = Color(0xFF6750A4);

  static final light = ThemeData(
    colorSchemeSeed: seed,
    brightness: Brightness.light,
    cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
  );

  static final dark = ThemeData(
    colorSchemeSeed: seed,
    brightness: Brightness.dark,
  );
}
