import 'dart:convert';

import 'package:flutter2figma/analyzer.dart';
import 'package:flutter2figma/ir.dart';

import 'text_style.dart';

enum ThemeBrightness { light, dark }

/// The subset of `AppBarThemeData` the exporter applies.
class AppBarThemeSpec {
  const AppBarThemeSpec({
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.centerTitle,
    this.titleTextStyle,
    this.toolbarHeight,
  });

  final IrColor? backgroundColor;
  final IrColor? foregroundColor;
  final double? elevation;
  final bool? centerTitle;
  final TextStyleSpec? titleTextStyle;
  final double? toolbarHeight;
}

/// The subset of `CardThemeData` the exporter applies.
class CardThemeSpec {
  const CardThemeSpec({this.color, this.elevation, this.margin, this.shape});

  final IrColor? color;
  final double? elevation;
  final IrInsets? margin;

  /// Unevaluated `ShapeBorder`, interpreted like a widget's `shape:`.
  final DartValue? shape;
}

/// A resolved Material 3 theme: what `Theme.of(context)` would return.
///
/// The default is `ThemeData()` (the M3 baseline), transcribed from the
/// Flutter SDK. `ThemeExtractor` builds one from the app's `ThemeData`.
class MaterialTheme {
  const MaterialTheme({
    this.brightness = ThemeBrightness.light,
    this.fontFamily = 'Roboto',
    this.colorScheme = m3LightColorScheme,
    this.textTheme = m3TextTheme,
    this.scaffoldBackground,
    this.appBar = const AppBarThemeSpec(),
    this.card = const CardThemeSpec(),
    this.buttonStyles = const {},
  });

  /// `ThemeData(brightness: b)` with no other arguments.
  factory MaterialTheme.baseline(ThemeBrightness b) => MaterialTheme(
    brightness: b,
    colorScheme: b == ThemeBrightness.dark
        ? m3DarkColorScheme
        : m3LightColorScheme,
  );

  final ThemeBrightness brightness;

  /// Font used when a text style names none.
  final String fontFamily;

  /// Every `ColorScheme` role as ARGB.
  final Map<String, int> colorScheme;

  /// Localized text theme entries (geometry + family + user overrides).
  /// Colors are only present when the app set them; see [textStyle].
  final Map<String, TextStyleSpec> textTheme;

  final IrColor? scaffoldBackground;
  final AppBarThemeSpec appBar;
  final CardThemeSpec card;

  /// `elevatedButtonTheme` etc.: button type → `ButtonStyle` arguments.
  final Map<String, Map<String, DartValue>> buttonStyles;

  bool get isDark => brightness == ThemeBrightness.dark;

  /// A color scheme role, tagged with its design token.
  IrColor color(String role) => maybeColor(role)!;

  IrColor? maybeColor(String role) {
    final argb = colorScheme[role];
    return argb == null
        ? null
        : IrColor.fromArgb32(argb, token: colorToken(role));
  }

  static String colorToken(String role) => 'ColorScheme/$role';
  static String textToken(String name) => 'TextTheme/$name';

  /// The text theme entry name for a `TextTheme/...` token.
  static String? textStyleName(String? token) =>
      token != null && token.startsWith('TextTheme/')
      ? token.substring(10)
      : null;

  /// A text theme entry as widgets see it. M3 typography colors every style
  /// `onSurface` unless the app's text theme says otherwise.
  TextStyleSpec? textStyle(String name) {
    final entry = textTheme[name];
    if (entry == null) return null;
    return TextStyleSpec(
      fontFamily: fontFamily,
      color: color('onSurface'),
      token: textToken(name),
    ).merge(entry);
  }

  /// Elevations representative of M3 levels 1–5 (see [shadows]).
  static const elevationLevels = [1.0, 3.0, 6.0, 8.0, 12.0];

  /// Effect style tokens for the M3 elevation levels.
  List<IrShadowToken> get shadowTokens => [
    for (var i = 0; i < elevationLevels.length; i++)
      IrShadowToken('Elevation/level${i + 1}', shadows(elevationLevels[i])),
  ];

  /// The elevation token [shadows] was produced from, if any.
  String? shadowToken(List<IrShadow> shadows) {
    if (shadows.isEmpty) return null;
    final key = jsonEncodeShadows(shadows);
    for (final t in shadowTokens) {
      if (jsonEncodeShadows(t.shadows) == key) return t.name;
    }
    return null;
  }

  /// Figma approximation of Material 3 elevation levels (M3 design kit).
  List<IrShadow> shadows(double elevation) {
    if (elevation <= 0) return const [];
    final (
      keyY,
      keyBlur,
      ambientY,
      ambientBlur,
      ambientSpread,
    ) = switch (elevation) {
      <= 1 => (1.0, 2.0, 1.0, 3.0, 1.0),
      <= 3 => (1.0, 2.0, 2.0, 6.0, 2.0),
      <= 6 => (1.0, 3.0, 4.0, 8.0, 3.0),
      <= 8 => (2.0, 3.0, 6.0, 10.0, 4.0),
      _ => (4.0, 4.0, 8.0, 12.0, 6.0),
    };
    final shadow = color('shadow');
    return [
      IrShadow(color: shadow.withAlpha(0.3), y: keyY, blur: keyBlur),
      IrShadow(
        color: shadow.withAlpha(0.15),
        y: ambientY,
        blur: ambientBlur,
        spread: ambientSpread,
      ),
    ];
  }
}

// Generated from `_colorSchemeLightM3` / `_colorSchemeDarkM3` in the Flutter
// SDK's theme_data.dart. Regenerate rather than edit by hand.
const m3LightColorScheme = <String, int>{
  'primary': 0xFF6750A4,
  'onPrimary': 0xFFFFFFFF,
  'primaryContainer': 0xFFEADDFF,
  'onPrimaryContainer': 0xFF4F378B,
  'primaryFixed': 0xFFEADDFF,
  'primaryFixedDim': 0xFFD0BCFF,
  'onPrimaryFixed': 0xFF21005D,
  'onPrimaryFixedVariant': 0xFF4F378B,
  'secondary': 0xFF625B71,
  'onSecondary': 0xFFFFFFFF,
  'secondaryContainer': 0xFFE8DEF8,
  'onSecondaryContainer': 0xFF4A4458,
  'secondaryFixed': 0xFFE8DEF8,
  'secondaryFixedDim': 0xFFCCC2DC,
  'onSecondaryFixed': 0xFF1D192B,
  'onSecondaryFixedVariant': 0xFF4A4458,
  'tertiary': 0xFF7D5260,
  'onTertiary': 0xFFFFFFFF,
  'tertiaryContainer': 0xFFFFD8E4,
  'onTertiaryContainer': 0xFF633B48,
  'tertiaryFixed': 0xFFFFD8E4,
  'tertiaryFixedDim': 0xFFEFB8C8,
  'onTertiaryFixed': 0xFF31111D,
  'onTertiaryFixedVariant': 0xFF633B48,
  'error': 0xFFB3261E,
  'onError': 0xFFFFFFFF,
  'errorContainer': 0xFFF9DEDC,
  'onErrorContainer': 0xFF8C1D18,
  'background': 0xFFFEF7FF,
  'onBackground': 0xFF1D1B20,
  'surface': 0xFFFEF7FF,
  'surfaceBright': 0xFFFEF7FF,
  'surfaceContainerLowest': 0xFFFFFFFF,
  'surfaceContainerLow': 0xFFF7F2FA,
  'surfaceContainer': 0xFFF3EDF7,
  'surfaceContainerHigh': 0xFFECE6F0,
  'surfaceContainerHighest': 0xFFE6E0E9,
  'surfaceDim': 0xFFDED8E1,
  'onSurface': 0xFF1D1B20,
  'surfaceVariant': 0xFFE7E0EC,
  'onSurfaceVariant': 0xFF49454F,
  'outline': 0xFF79747E,
  'outlineVariant': 0xFFCAC4D0,
  'shadow': 0xFF000000,
  'scrim': 0xFF000000,
  'inverseSurface': 0xFF322F35,
  'onInverseSurface': 0xFFF5EFF7,
  'inversePrimary': 0xFFD0BCFF,
  'surfaceTint': 0xFF6750A4,
};
const m3DarkColorScheme = <String, int>{
  'primary': 0xFFD0BCFF,
  'onPrimary': 0xFF381E72,
  'primaryContainer': 0xFF4F378B,
  'onPrimaryContainer': 0xFFEADDFF,
  'primaryFixed': 0xFFEADDFF,
  'primaryFixedDim': 0xFFD0BCFF,
  'onPrimaryFixed': 0xFF21005D,
  'onPrimaryFixedVariant': 0xFF4F378B,
  'secondary': 0xFFCCC2DC,
  'onSecondary': 0xFF332D41,
  'secondaryContainer': 0xFF4A4458,
  'onSecondaryContainer': 0xFFE8DEF8,
  'secondaryFixed': 0xFFE8DEF8,
  'secondaryFixedDim': 0xFFCCC2DC,
  'onSecondaryFixed': 0xFF1D192B,
  'onSecondaryFixedVariant': 0xFF4A4458,
  'tertiary': 0xFFEFB8C8,
  'onTertiary': 0xFF492532,
  'tertiaryContainer': 0xFF633B48,
  'onTertiaryContainer': 0xFFFFD8E4,
  'tertiaryFixed': 0xFFFFD8E4,
  'tertiaryFixedDim': 0xFFEFB8C8,
  'onTertiaryFixed': 0xFF31111D,
  'onTertiaryFixedVariant': 0xFF633B48,
  'error': 0xFFF2B8B5,
  'onError': 0xFF601410,
  'errorContainer': 0xFF8C1D18,
  'onErrorContainer': 0xFFF9DEDC,
  'background': 0xFF141218,
  'onBackground': 0xFFE6E0E9,
  'surface': 0xFF141218,
  'surfaceBright': 0xFF3B383E,
  'surfaceContainerLowest': 0xFF0F0D13,
  'surfaceContainerLow': 0xFF1D1B20,
  'surfaceContainer': 0xFF211F26,
  'surfaceContainerHigh': 0xFF2B2930,
  'surfaceContainerHighest': 0xFF36343B,
  'surfaceDim': 0xFF141218,
  'onSurface': 0xFFE6E0E9,
  'surfaceVariant': 0xFF49454F,
  'onSurfaceVariant': 0xFFCAC4D0,
  'outline': 0xFF938F99,
  'outlineVariant': 0xFF49454F,
  'shadow': 0xFF000000,
  'scrim': 0xFF000000,
  'inverseSurface': 0xFFE6E0E9,
  'onInverseSurface': 0xFF322F35,
  'inversePrimary': 0xFF6750A4,
  'surfaceTint': 0xFFD0BCFF,
};

const m3TextTheme = <String, TextStyleSpec>{
  'displayLarge': TextStyleSpec(
    fontSize: 57,
    fontWeight: 400,
    letterSpacing: -0.25,
    height: 1.12,
  ),
  'displayMedium': TextStyleSpec(
    fontSize: 45,
    fontWeight: 400,
    letterSpacing: 0,
    height: 1.16,
  ),
  'displaySmall': TextStyleSpec(
    fontSize: 36,
    fontWeight: 400,
    letterSpacing: 0,
    height: 1.22,
  ),
  'headlineLarge': TextStyleSpec(
    fontSize: 32,
    fontWeight: 400,
    letterSpacing: 0,
    height: 1.25,
  ),
  'headlineMedium': TextStyleSpec(
    fontSize: 28,
    fontWeight: 400,
    letterSpacing: 0,
    height: 1.29,
  ),
  'headlineSmall': TextStyleSpec(
    fontSize: 24,
    fontWeight: 400,
    letterSpacing: 0,
    height: 1.33,
  ),
  'titleLarge': TextStyleSpec(
    fontSize: 22,
    fontWeight: 400,
    letterSpacing: 0,
    height: 1.27,
  ),
  'titleMedium': TextStyleSpec(
    fontSize: 16,
    fontWeight: 500,
    letterSpacing: 0.15,
    height: 1.50,
  ),
  'titleSmall': TextStyleSpec(
    fontSize: 14,
    fontWeight: 500,
    letterSpacing: 0.1,
    height: 1.43,
  ),
  'labelLarge': TextStyleSpec(
    fontSize: 14,
    fontWeight: 500,
    letterSpacing: 0.1,
    height: 1.43,
  ),
  'labelMedium': TextStyleSpec(
    fontSize: 12,
    fontWeight: 500,
    letterSpacing: 0.5,
    height: 1.33,
  ),
  'labelSmall': TextStyleSpec(
    fontSize: 11,
    fontWeight: 500,
    letterSpacing: 0.5,
    height: 1.45,
  ),
  'bodyLarge': TextStyleSpec(
    fontSize: 16,
    fontWeight: 400,
    letterSpacing: 0.5,
    height: 1.50,
  ),
  'bodyMedium': TextStyleSpec(
    fontSize: 14,
    fontWeight: 400,
    letterSpacing: 0.25,
    height: 1.43,
  ),
  'bodySmall': TextStyleSpec(
    fontSize: 12,
    fontWeight: 400,
    letterSpacing: 0.4,
    height: 1.33,
  ),
};

String jsonEncodeShadows(List<IrShadow> shadows) =>
    jsonEncode([for (final s in shadows) s.toJson()]);

/// The theme in the same shape as the Flutter ground-truth dump
/// (`example/test/theme_ground_truth_test.dart`), for comparing the
/// static extraction with what Flutter resolves.
Map<String, Object?> describeTheme(MaterialTheme t) {
  String hex(IrColor? c) => c?.toHex() ?? 'null';
  const deprecated = {'background', 'onBackground', 'surfaceVariant'};
  return {
    'colorScheme': {
      'brightness': t.brightness.name,
      for (final role in t.colorScheme.keys)
        if (!deprecated.contains(role)) role: hex(t.color(role)),
    },
    'textTheme': {
      for (final name in m3TextTheme.keys)
        name: switch (t.textStyle(name)!) {
          final s => {
            'fontFamily': s.fontFamily,
            'fontSize': s.fontSize,
            'fontWeight': s.fontWeight,
            'height': s.height,
            'letterSpacing': s.letterSpacing,
            'color': hex(s.color),
          },
        },
    },
    'scaffoldBackgroundColor': hex(t.scaffoldBackground ?? t.color('surface')),
    'appBar': {
      'backgroundColor': hex(t.appBar.backgroundColor),
      'foregroundColor': hex(t.appBar.foregroundColor),
      'elevation': t.appBar.elevation,
      'centerTitle': t.appBar.centerTitle,
    },
    'card': {'color': hex(t.card.color), 'elevation': t.card.elevation},
  };
}
