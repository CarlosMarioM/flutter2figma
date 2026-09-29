/// Reproduces how Flutter builds a `ColorScheme`, so an app's scheme can be
/// computed statically. Rules transcribed from the Flutter SDK's
/// `color_scheme.dart`.
library;

import 'package:material_color_utilities/material_color_utilities.dart';

import 'material_theme.dart';

/// Optional roles in declaration order, each with the role (or ARGB constant)
/// its getter falls back to when unset. Order matters: a fallback must
/// already be resolved (e.g. `tertiary` before `tertiaryContainer`).
const _fallbacks = <(String, Object)>[
  ('primaryContainer', 'primary'),
  ('onPrimaryContainer', 'onPrimary'),
  ('primaryFixed', 'primary'),
  ('primaryFixedDim', 'primary'),
  ('onPrimaryFixed', 'onPrimary'),
  ('onPrimaryFixedVariant', 'onPrimary'),
  ('secondaryContainer', 'secondary'),
  ('onSecondaryContainer', 'onSecondary'),
  ('secondaryFixed', 'secondary'),
  ('secondaryFixedDim', 'secondary'),
  ('onSecondaryFixed', 'onSecondary'),
  ('onSecondaryFixedVariant', 'onSecondary'),
  ('tertiary', 'secondary'),
  ('onTertiary', 'onSecondary'),
  ('tertiaryContainer', 'tertiary'),
  ('onTertiaryContainer', 'onTertiary'),
  ('tertiaryFixed', 'tertiary'),
  ('tertiaryFixedDim', 'tertiary'),
  ('onTertiaryFixed', 'onTertiary'),
  ('onTertiaryFixedVariant', 'onTertiary'),
  ('errorContainer', 'error'),
  ('onErrorContainer', 'onError'),
  ('background', 'surface'),
  ('onBackground', 'onSurface'),
  ('surfaceVariant', 'surface'),
  ('surfaceDim', 'surface'),
  ('surfaceBright', 'surface'),
  ('surfaceContainerLowest', 'surface'),
  ('surfaceContainerLow', 'surface'),
  ('surfaceContainer', 'surface'),
  ('surfaceContainerHigh', 'surface'),
  ('surfaceContainerHighest', 'surface'),
  ('onSurfaceVariant', 'onSurface'),
  ('outline', 'onBackground'),
  ('outlineVariant', 'onBackground'),
  ('shadow', 0xFF000000),
  ('scrim', 0xFF000000),
  ('inverseSurface', 'onSurface'),
  ('onInverseSurface', 'surface'),
  ('inversePrimary', 'onPrimary'),
  ('surfaceTint', 'primary'),
];

/// Roles every `ColorScheme` constructor requires.
const requiredColorRoles = [
  'primary',
  'onPrimary',
  'secondary',
  'onSecondary',
  'error',
  'onError',
  'surface',
  'onSurface',
];

/// All roles a complete scheme has.
final allColorRoles = [
  ...requiredColorRoles,
  for (final (r, _) in _fallbacks) r,
];

/// Defaults of `ColorScheme.light()` / `ColorScheme.dark()` (Material 2
/// baseline colors; the M3 roles fall back as in the main constructor).
const colorSchemeLightDefaults = {
  'primary': 0xFF6200EE,
  'onPrimary': 0xFFFFFFFF,
  'secondary': 0xFF03DAC6,
  'onSecondary': 0xFF000000,
  'error': 0xFFB00020,
  'onError': 0xFFFFFFFF,
  'surface': 0xFFFFFFFF,
  'onSurface': 0xFF000000,
  'background': 0xFFFFFFFF,
  'onBackground': 0xFF000000,
};

const colorSchemeDarkDefaults = {
  'primary': 0xFFBB86FC,
  'onPrimary': 0xFF000000,
  'secondary': 0xFF03DAC6,
  'onSecondary': 0xFF000000,
  'error': 0xFFCF6679,
  'onError': 0xFF000000,
  'surface': 0xFF121212,
  'onSurface': 0xFFFFFFFF,
  'background': 0xFF121212,
  'onBackground': 0xFFFFFFFF,
};

/// Fills unset optional roles the way `ColorScheme`'s getters do.
/// Returns null if a required role is missing.
Map<String, int>? completeColorScheme(Map<String, int> given) {
  if (!requiredColorRoles.every(given.containsKey)) return null;
  final out = {...given};
  for (final (role, fallback) in _fallbacks) {
    out[role] ??= fallback is int ? fallback : out[fallback as String]!;
  }
  return out;
}

/// `ColorScheme.fromSeed`: roles come from Material Color Utilities' dynamic
/// scheme, then explicit [overrides] win.
Map<String, int> seedColorScheme(
  int seedArgb, {
  required ThemeBrightness brightness,
  String variant = 'tonalSpot',
  double contrastLevel = 0,
  Map<String, int> overrides = const {},
}) {
  final isDark = brightness == ThemeBrightness.dark;
  final source = Hct.fromInt(seedArgb);
  final DynamicScheme scheme = switch (variant) {
    'fidelity' => SchemeFidelity(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    'content' => SchemeContent(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    'monochrome' => SchemeMonochrome(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    'neutral' => SchemeNeutral(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    'vibrant' => SchemeVibrant(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    'expressive' => SchemeExpressive(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    'rainbow' => SchemeRainbow(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    'fruitSalad' => SchemeFruitSalad(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    _ => SchemeTonalSpot(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
  };
  return {
    for (final MapEntry(key: role, value: color) in _dynamicColors.entries)
      role: overrides[role] ?? color.getArgb(scheme),
  };
}

/// `ColorScheme` role → the dynamic color `ColorScheme.fromSeed` reads.
final _dynamicColors = <String, DynamicColor>{
  'primary': MaterialDynamicColors.primary,
  'onPrimary': MaterialDynamicColors.onPrimary,
  'primaryContainer': MaterialDynamicColors.primaryContainer,
  'onPrimaryContainer': MaterialDynamicColors.onPrimaryContainer,
  'primaryFixed': MaterialDynamicColors.primaryFixed,
  'primaryFixedDim': MaterialDynamicColors.primaryFixedDim,
  'onPrimaryFixed': MaterialDynamicColors.onPrimaryFixed,
  'onPrimaryFixedVariant': MaterialDynamicColors.onPrimaryFixedVariant,
  'secondary': MaterialDynamicColors.secondary,
  'onSecondary': MaterialDynamicColors.onSecondary,
  'secondaryContainer': MaterialDynamicColors.secondaryContainer,
  'onSecondaryContainer': MaterialDynamicColors.onSecondaryContainer,
  'secondaryFixed': MaterialDynamicColors.secondaryFixed,
  'secondaryFixedDim': MaterialDynamicColors.secondaryFixedDim,
  'onSecondaryFixed': MaterialDynamicColors.onSecondaryFixed,
  'onSecondaryFixedVariant': MaterialDynamicColors.onSecondaryFixedVariant,
  'tertiary': MaterialDynamicColors.tertiary,
  'onTertiary': MaterialDynamicColors.onTertiary,
  'tertiaryContainer': MaterialDynamicColors.tertiaryContainer,
  'onTertiaryContainer': MaterialDynamicColors.onTertiaryContainer,
  'tertiaryFixed': MaterialDynamicColors.tertiaryFixed,
  'tertiaryFixedDim': MaterialDynamicColors.tertiaryFixedDim,
  'onTertiaryFixed': MaterialDynamicColors.onTertiaryFixed,
  'onTertiaryFixedVariant': MaterialDynamicColors.onTertiaryFixedVariant,
  'error': MaterialDynamicColors.error,
  'onError': MaterialDynamicColors.onError,
  'errorContainer': MaterialDynamicColors.errorContainer,
  'onErrorContainer': MaterialDynamicColors.onErrorContainer,
  'outline': MaterialDynamicColors.outline,
  'outlineVariant': MaterialDynamicColors.outlineVariant,
  'surface': MaterialDynamicColors.surface,
  'surfaceDim': MaterialDynamicColors.surfaceDim,
  'surfaceBright': MaterialDynamicColors.surfaceBright,
  'surfaceContainerLowest': MaterialDynamicColors.surfaceContainerLowest,
  'surfaceContainerLow': MaterialDynamicColors.surfaceContainerLow,
  'surfaceContainer': MaterialDynamicColors.surfaceContainer,
  'surfaceContainerHigh': MaterialDynamicColors.surfaceContainerHigh,
  'surfaceContainerHighest': MaterialDynamicColors.surfaceContainerHighest,
  'onSurface': MaterialDynamicColors.onSurface,
  'onSurfaceVariant': MaterialDynamicColors.onSurfaceVariant,
  'inverseSurface': MaterialDynamicColors.inverseSurface,
  // Flutter's name differs from the utilities' name for these two.
  'onInverseSurface': MaterialDynamicColors.inverseOnSurface,
  'inversePrimary': MaterialDynamicColors.inversePrimary,
  'shadow': MaterialDynamicColors.shadow,
  'scrim': MaterialDynamicColors.scrim,
  'surfaceTint': MaterialDynamicColors.primary,
  'background': MaterialDynamicColors.background,
  'onBackground': MaterialDynamicColors.onBackground,
  'surfaceVariant': MaterialDynamicColors.surfaceVariant,
};
