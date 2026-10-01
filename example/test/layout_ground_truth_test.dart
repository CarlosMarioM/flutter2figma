// Ground truth for layout: sizes Flutter actually lays out on a 390×844
// screen, written to test/goldens/basic_layout.json (repo root). The plugin
// test imports the exported design into its layout-aware Figma mock and must
// produce the same sizes, so Flutter and Figma agree on real numbers.
//
// Regenerate with: UPDATE_GOLDENS=1 fvm flutter test test/layout_ground_truth_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter2figma_example/home_screen.dart';
import 'package:flutter2figma_example/scoreboard_screen.dart';
import 'package:flutter2figma_example/stack_layout_screen.dart';
import 'package:flutter2figma_example/theme.dart';

const fixturePath = '../test/goldens/basic_layout.json';

List<double> sizeOf(WidgetTester tester, Finder finder) {
  final size = tester.getSize(finder);
  return [size.width, size.height];
}

void main() {
  testWidgets('layout sizes match the fixture', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> show(Widget screen) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
      await tester.pump();
    }

    final sizes = <String, List<double>>{};

    await show(const HomeScreen());
    // Tap target: drawn 40 px tall, laid out 48 px tall.
    sizes['HomeScreen/ElevatedButton'] = sizeOf(
      tester,
      find.byType(ElevatedButton),
    );

    await show(const StackLayoutScreen());
    sizes['StackLayoutScreen/header'] = sizeOf(
      tester,
      find.byWidgetPredicate(
        (w) => w is Container && w.color == const Color(0xFF423F9A),
      ),
    );
    sizes['StackLayoutScreen/body'] = sizeOf(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration == const BoxDecoration(color: Colors.white),
      ),
    );
    sizes['StackLayoutScreen/IconButton'] = sizeOf(
      tester,
      find.byType(IconButton),
    );

    await show(const ScoreboardScreen());
    sizes['ScoreboardScreen/Switch'] = sizeOf(tester, find.byType(Switch));
    sizes['ScoreboardScreen/Checkbox'] = sizeOf(tester, find.byType(Checkbox));

    final actual = '${const JsonEncoder.withIndent('  ').convert(sizes)}\n';
    final fixture = File(fixturePath);
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      fixture.writeAsStringSync(actual);
    }
    expect(actual, fixture.readAsStringSync());
  });
}
