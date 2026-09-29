import 'dart:convert';
import 'dart:io';

import 'package:flutter2figma/analyzer.dart';
import 'package:flutter2figma/compiler.dart';
import 'package:flutter2figma/ir.dart';
import 'package:test/test.dart';

/// The static theme extraction must match what Flutter itself resolves.
///
/// `test/goldens/basic_theme.json` is written by the Flutter test
/// `example/test/theme_ground_truth_test.dart`, which pumps the real
/// app and dumps `Theme.of(context)`.
void main() {
  late ProjectAnalysis analysis;
  late Map<String, Object?> groundTruth;

  setUpAll(() async {
    analysis = await FlutterProjectAnalyzer('example').analyze();
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
      final actual = describeTheme(theme);
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
