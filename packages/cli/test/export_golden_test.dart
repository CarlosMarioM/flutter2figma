import 'dart:convert';
import 'dart:io';

import 'package:flutter2figma_analyzer/flutter2figma_analyzer.dart';
import 'package:flutter2figma_compiler/flutter2figma_compiler.dart';
import 'package:flutter2figma_figma/flutter2figma_figma.dart';
import 'package:test/test.dart';

/// End-to-end: examples/basic → design.json, compared with a checked-in
/// golden. The Figma plugin tests import the same golden.
///
/// Regenerate with: UPDATE_GOLDENS=1 dart test
void main() {
  test(
    'examples/basic exports the expected design.json',
    () async {
      final analysis = await FlutterProjectAnalyzer(
        '../../examples/basic',
      ).analyze();
      final ir = FlutterCompiler().compile(analysis);
      final design = FigmaRenderer().render(ir);
      final actual = '${const JsonEncoder.withIndent('  ').convert(design)}\n';

      final golden = File('test/goldens/basic.design.json');
      if (Platform.environment['UPDATE_GOLDENS'] == '1') {
        golden
          ..createSync(recursive: true)
          ..writeAsStringSync(actual);
      }
      expect(
        golden.existsSync(),
        isTrue,
        reason: 'Missing golden; run with UPDATE_GOLDENS=1',
      );
      expect(actual, golden.readAsStringSync());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
