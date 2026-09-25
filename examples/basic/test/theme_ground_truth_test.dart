// Ground truth for Flutter2Figma's theme extraction.
//
// Pumps the real app, reads the theme widgets actually render with, and
// compares it with packages/compiler/test/goldens/basic_theme.json. The
// compiler's theme extraction test checks its static result against the same
// file, so both sides agree on one fixture.
//
// Regenerate with: UPDATE_GOLDENS=1 fvm flutter test test/theme_ground_truth_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:basic/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const fixturePath = '../../packages/compiler/test/goldens/basic_theme.json';

String hex(Color? c) {
  if (c == null) return 'null';
  final argb = c.toARGB32();
  String h(int v) => v.toRadixString(16).padLeft(2, '0');
  final a = (argb >> 24) & 0xff;
  return '#${h((argb >> 16) & 0xff)}${h((argb >> 8) & 0xff)}${h(argb & 0xff)}${a == 0xff ? '' : h(a)}'
      .toUpperCase();
}

Map<String, Object?> scheme(ColorScheme s) => {
  'brightness': s.brightness.name,
  for (final MapEntry(:key, :value) in {
    'primary': s.primary,
    'onPrimary': s.onPrimary,
    'primaryContainer': s.primaryContainer,
    'onPrimaryContainer': s.onPrimaryContainer,
    'primaryFixed': s.primaryFixed,
    'primaryFixedDim': s.primaryFixedDim,
    'onPrimaryFixed': s.onPrimaryFixed,
    'onPrimaryFixedVariant': s.onPrimaryFixedVariant,
    'secondary': s.secondary,
    'onSecondary': s.onSecondary,
    'secondaryContainer': s.secondaryContainer,
    'onSecondaryContainer': s.onSecondaryContainer,
    'secondaryFixed': s.secondaryFixed,
    'secondaryFixedDim': s.secondaryFixedDim,
    'onSecondaryFixed': s.onSecondaryFixed,
    'onSecondaryFixedVariant': s.onSecondaryFixedVariant,
    'tertiary': s.tertiary,
    'onTertiary': s.onTertiary,
    'tertiaryContainer': s.tertiaryContainer,
    'onTertiaryContainer': s.onTertiaryContainer,
    'tertiaryFixed': s.tertiaryFixed,
    'tertiaryFixedDim': s.tertiaryFixedDim,
    'onTertiaryFixed': s.onTertiaryFixed,
    'onTertiaryFixedVariant': s.onTertiaryFixedVariant,
    'error': s.error,
    'onError': s.onError,
    'errorContainer': s.errorContainer,
    'onErrorContainer': s.onErrorContainer,
    'surface': s.surface,
    'onSurface': s.onSurface,
    'surfaceDim': s.surfaceDim,
    'surfaceBright': s.surfaceBright,
    'surfaceContainerLowest': s.surfaceContainerLowest,
    'surfaceContainerLow': s.surfaceContainerLow,
    'surfaceContainer': s.surfaceContainer,
    'surfaceContainerHigh': s.surfaceContainerHigh,
    'surfaceContainerHighest': s.surfaceContainerHighest,
    'onSurfaceVariant': s.onSurfaceVariant,
    'outline': s.outline,
    'outlineVariant': s.outlineVariant,
    'shadow': s.shadow,
    'scrim': s.scrim,
    'inverseSurface': s.inverseSurface,
    'onInverseSurface': s.onInverseSurface,
    'inversePrimary': s.inversePrimary,
    'surfaceTint': s.surfaceTint,
  }.entries)
    key: hex(value),
};

Map<String, Object?> style(TextStyle? t) => {
  'fontFamily': t?.fontFamily,
  'fontSize': t?.fontSize,
  'fontWeight': t?.fontWeight?.value,
  'height': t?.height,
  'letterSpacing': t?.letterSpacing,
  'color': hex(t?.color),
};

Map<String, Object?> theme(ThemeData t) => {
  'colorScheme': scheme(t.colorScheme),
  'textTheme': {
    'displayLarge': style(t.textTheme.displayLarge),
    'displayMedium': style(t.textTheme.displayMedium),
    'displaySmall': style(t.textTheme.displaySmall),
    'headlineLarge': style(t.textTheme.headlineLarge),
    'headlineMedium': style(t.textTheme.headlineMedium),
    'headlineSmall': style(t.textTheme.headlineSmall),
    'titleLarge': style(t.textTheme.titleLarge),
    'titleMedium': style(t.textTheme.titleMedium),
    'titleSmall': style(t.textTheme.titleSmall),
    'bodyLarge': style(t.textTheme.bodyLarge),
    'bodyMedium': style(t.textTheme.bodyMedium),
    'bodySmall': style(t.textTheme.bodySmall),
    'labelLarge': style(t.textTheme.labelLarge),
    'labelMedium': style(t.textTheme.labelMedium),
    'labelSmall': style(t.textTheme.labelSmall),
  },
  'scaffoldBackgroundColor': hex(t.scaffoldBackgroundColor),
  'appBar': {
    'backgroundColor': hex(t.appBarTheme.backgroundColor),
    'foregroundColor': hex(t.appBarTheme.foregroundColor),
    'elevation': t.appBarTheme.elevation,
    'centerTitle': t.appBarTheme.centerTitle,
  },
  'card': {
    'color': hex(t.cardTheme.color),
    'elevation': t.cardTheme.elevation,
  },
};

void main() {
  testWidgets('resolved app theme matches the extraction fixture', (tester) async {
    // Theme.of(context) is what widgets render with: MaterialApp's ThemeData
    // localized with the typography geometry (font sizes, heights).
    Future<ThemeData> resolved(Brightness platformBrightness) async {
      tester.platformDispatcher.platformBrightnessTestValue = platformBrightness;
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();
      return Theme.of(tester.element(find.byType(Scaffold).first));
    }

    final light = theme(await resolved(Brightness.light));
    final dark = theme(await resolved(Brightness.dark));
    tester.platformDispatcher.clearPlatformBrightnessTestValue();

    final actual = '${const JsonEncoder.withIndent('  ').convert({
      'light': light,
      'dark': dark,
    })}\n';

    final fixture = File(fixturePath);
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      fixture
        ..createSync(recursive: true)
        ..writeAsStringSync(actual);
    }
    expect(actual, fixture.readAsStringSync());
  });
}
