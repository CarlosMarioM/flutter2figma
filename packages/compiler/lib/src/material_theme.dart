import 'package:flutter2figma_ir/flutter2figma_ir.dart';

import 'text_style.dart';

/// Material 3 defaults, transcribed from the Flutter SDK
/// (`theme_data.dart` `_colorSchemeLightM3`, `typography.dart` `_M3Typography`).
///
/// Used when a widget doesn't specify a value and Flutter would fall back to
/// `ThemeData()`.
class MaterialTheme {
  const MaterialTheme({
    this.fontFamily = 'Roboto',
    this.colorScheme = m3LightColorScheme,
    this.textTheme = m3TextTheme,
  });

  final String fontFamily;
  final Map<String, int> colorScheme;
  final Map<String, TextStyleSpec> textTheme;

  IrColor color(String role) => IrColor.fromArgb32(colorScheme[role]!);

  IrColor? maybeColor(String role) {
    final argb = colorScheme[role];
    return argb == null ? null : IrColor.fromArgb32(argb);
  }

  /// A text theme entry, colored like `ThemeData.textTheme` (onSurface).
  TextStyleSpec? textStyle(String name) =>
      textTheme[name]?.merge(TextStyleSpec(color: color('onSurface')));

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

const m3LightColorScheme = <String, int>{
  'primary': 0xFF6750A4,
  'onPrimary': 0xFFFFFFFF,
  'primaryContainer': 0xFFEADDFF,
  'onPrimaryContainer': 0xFF4F378B,
  'secondary': 0xFF625B71,
  'onSecondary': 0xFFFFFFFF,
  'secondaryContainer': 0xFFE8DEF8,
  'onSecondaryContainer': 0xFF4A4458,
  'tertiary': 0xFF7D5260,
  'onTertiary': 0xFFFFFFFF,
  'tertiaryContainer': 0xFFFFD8E4,
  'onTertiaryContainer': 0xFF633B48,
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
