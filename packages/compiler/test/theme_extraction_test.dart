import 'dart:convert';
import 'dart:io';

import 'package:flutter2figma_analyzer/flutter2figma_analyzer.dart';
import 'package:flutter2figma_compiler/flutter2figma_compiler.dart';
import 'package:flutter2figma_ir/flutter2figma_ir.dart';
import 'package:test/test.dart';

/// The static theme extraction must match what Flutter itself resolves.
///
/// `test/goldens/basic_theme.json` is written by the Flutter test
/// `examples/basic/test/theme_ground_truth_test.dart`, which pumps the real
/// app and dumps `Theme.of(context)`.
void main() {
  late ProjectAnalysis analysis;
  late Map<String, Object?> groundTruth;

  setUpAll(() async {
    analysis = await FlutterProjectAnalyzer('../../examples/basic').analyze();
    groundTruth =
        jsonDecode(File('test/goldens/basic_theme.json').readAsStringSync())
            as Map<String, Object?>;
  });

  for (final brightness in ThemeBrightness.values) {
    test('${brightness.name} theme matches Flutter', () {
      final extractor = ThemeExtractor(ValueEvaluator(const MaterialTheme()));
      final theme = extractor.fromProject(analysis, brightness: brightness);
      expect(extractor.diagnostics, isEmpty);

      final expected = groundTruth[brightness.name] as Map<String, Object?>;
      final actual = dump(theme);
      for (final section in expected.keys) {
        expect(actual[section], expected[section], reason: section);
      }
    });
  }

  test('baseline theme when there is no MaterialApp', () {
    final extractor = ThemeExtractor(ValueEvaluator(const MaterialTheme()));
    final theme = extractor.fromProject(
      ProjectAnalysis(
        name: 'x',
        root: '.',
        files: const [],
        widgets: const [],
        diagnostics: const [],
      ),
    );
    expect(theme.color('primary').toHex(), '#6750A4');
    expect(extractor.diagnostics.single.severity, IrSeverity.info);
  });
}

/// Same shape as the Flutter-side dump.
Map<String, Object?> dump(MaterialTheme t) {
  String hex(IrColor? c) => c?.toHex() ?? 'null';
  final expectedRoles =
      ((jsonDecode(File('test/goldens/basic_theme.json').readAsStringSync())
                  as Map)['light']
              as Map)['colorScheme']
          as Map;
  return {
    'colorScheme': {
      'brightness': t.brightness.name,
      for (final role in expectedRoles.keys.where((k) => k != 'brightness'))
        role: hex(t.color(role as String)),
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
