import 'dart:convert';
import 'dart:io';

import 'package:flutter2figma/analyzer.dart';
import 'package:flutter2figma/compiler.dart';
import 'package:flutter2figma/ir.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'builders.dart';

/// Material icons from the Flutter SDK the example resolves against.
final fonts = projectIconFonts('example');

void expectBounds(IconGlyph g, List<double> xywh) {
  expect(
    [g.x, g.y, g.width, g.height],
    [for (final v in xywh) closeTo(v, 0.05)],
  );
}

ObjectValue icon(int codePoint, {String family = 'MaterialIcons'}) => w(
  'Icon',
  positional: [
    ref(
      'Icons.glyph',
      resolved: v(
        'IconData',
        positional: [lit(codePoint)],
        named: {'fontFamily': lit(family)},
      ),
    ),
  ],
);

void main() {
  test('finds Flutter\'s Material icons font', () {
    expect(fonts.keys, contains('MaterialIcons'));
  });

  test('CFF glyphs land where Flutter draws them', () {
    final material = fonts['MaterialIcons']!;
    // Bounds of the Material Design sources, on their 24 px grid (the font
    // rounds outlines to its 512-unit em).
    expectBounds(material.glyph(0xe047, 24)!, [5, 5, 14, 14]); // add
    expectBounds(material.glyph(0xe093, 24)!, [
      0,
      2.1,
      11.67,
      19.8,
    ]); // arrow_back_ios
    // Scales with the icon size.
    expectBounds(material.glyph(0xe047, 48)!, [10.03, 10.03, 27.94, 27.94]);
    expect(material.glyph(0x41, 24), isNull); // no glyph for 'A'
  });

  test('TrueType glyphs', () {
    // Roboto ships next to the Material icons font, as TrueType.
    final roboto = IconFont.load(
      p.join(
        _flutterSdk(),
        'bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
    )!;
    final i = roboto.glyph(0x49, 100)!; // 'I': one upright bar
    expect(i.path, startsWith('M '));
    expect(i.path, endsWith('Z'));
    expect(i.height, greaterThan(60));
    expect(i.width, lessThan(15));
    expect(roboto.glyph(0x20, 100)!.isEmpty, isTrue); // space has no ink
  });

  test('Icon compiles to a vector of its glyph', () {
    final compiler = FlutterCompiler(iconFonts: fonts);
    final frame =
        compiler
                .compileScreen(
                  'Test',
                  w('Scaffold', named: {'body': icon(0xe047)}),
                  null,
                )
                .root
                .children
                .single
            as IrFrame;
    expect(frame.name, 'Icon/glyph');
    expect(frame.direction, IrLayoutDirection.stack);
    expect(frame.fill, isNull);
    final vector = frame.children.single as IrVector;
    expect(vector.path, startsWith('M '));
    expect(vector.position!.left, closeTo(5, 0.05));
    expect(vector.width.value, closeTo(14, 0.05));
    expect(vector.fill!.token, 'ColorScheme/onSurfaceVariant');
  });

  test('an icon picked by an unknown condition shows the true branch', () {
    final compiler = FlutterCompiler(iconFonts: fonts);
    final chosen = w(
      'Icon',
      positional: [
        ConditionalValue('muted', icon(0xe047).arg(0)!, icon(0xe093).arg(0)!),
      ],
    );
    final frame =
        compiler
                .compileScreen(
                  'Test',
                  w('Scaffold', named: {'body': chosen}),
                  null,
                )
                .root
                .children
                .single
            as IrFrame;
    expect(frame.name, 'Icon/glyph');
    expect((frame.children.single as IrVector).width.value, closeTo(14, 0.05));
  });

  test('icons in unknown fonts stay placeholders', () {
    final frame = body(icon(0xe900, family: 'AppIcons')) as IrFrame;
    expect(frame.children, isEmpty);
    expect(frame.fill, isNotNull);
  });
}

/// The Flutter SDK the example resolves against.
String _flutterSdk() {
  final config = File('example/.dart_tool/package_config.json');
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
  final flutter = packages.firstWhere((pkg) => pkg['name'] == 'flutter');
  final package = config.parent.uri.resolve(flutter['rootUri'] as String);
  return p.normalize(p.join(package.toFilePath(), '..', '..'));
}
