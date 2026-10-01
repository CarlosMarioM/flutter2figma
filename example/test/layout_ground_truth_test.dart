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
import 'package:flutter2figma_example/contacts_screen.dart';
import 'package:flutter2figma_example/home_screen.dart';
import 'package:flutter2figma_example/profile_screen.dart';
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

    // Decode the asset images first, so they lay out at their real size.
    await show(const ProfileScreen());
    await tester.runAsync(() async {
      final context = tester.element(find.byType(ProfileScreen));
      await precacheImage(const AssetImage('assets/logo.png'), context);
      await precacheImage(const AssetImage('assets/avatar.png'), context);
    });
    await tester.pump();
    sizes['ProfileScreen/Image'] = sizeOf(tester, find.byType(Image));

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

    await show(const ContactsScreen());
    sizes['ContactsScreen/ListTile 1'] = sizeOf(
      tester,
      find.byType(ListTile).at(0),
    );
    sizes['ContactsScreen/ListTile 2'] = sizeOf(
      tester,
      find.byType(ListTile).at(1),
    );
    sizes['ContactsScreen/SwitchListTile'] = sizeOf(
      tester,
      find.byType(SwitchListTile),
    );
    // Chips are measured with their tap target, like buttons.
    sizes['ContactsScreen/Chip'] = sizeOf(tester, find.byType(Chip));
    sizes['ContactsScreen/FilterChip'] = sizeOf(
      tester,
      find.byType(FilterChip),
    );
    sizes['ContactsScreen/InputChip'] = sizeOf(tester, find.byType(InputChip));
    sizes['ContactsScreen/NavigationBar'] = sizeOf(
      tester,
      find.byType(NavigationBar),
    );

    final actual = '${const JsonEncoder.withIndent('  ').convert(sizes)}\n';
    final fixture = File(fixturePath);
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      fixture.writeAsStringSync(actual);
    }
    expect(actual, fixture.readAsStringSync());
  });
}
