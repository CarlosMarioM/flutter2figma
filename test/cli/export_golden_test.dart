import 'dart:convert';
import 'dart:io';

import 'package:flutter2figma/analyzer.dart';
import 'package:flutter2figma/compiler.dart';
import 'package:flutter2figma/figma.dart';
import 'package:test/test.dart';

/// End-to-end: example → design.json, compared with a checked-in
/// golden. The Figma plugin tests import the same golden.
///
/// Regenerate with: UPDATE_GOLDENS=1 dart test
void main() {
  test(
    'example exports the expected design.json',
    () async {
      final analysis = await FlutterProjectAnalyzer('example').analyze();
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
