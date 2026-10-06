import 'package:flutter2figma/analyzer.dart';
import 'package:flutter2figma/compiler.dart';
import 'package:flutter2figma/ir.dart';
import 'package:test/test.dart';

/// The theme Flutter rendered with (as `harness.dart` records it).
Map<String, Object?> rendered({String brightness = 'light'}) => {
  'brightness': brightness,
  'colorScheme': {'primary': '#ffad8b73'},
  'textTheme': {
    'bodyMedium': {'family': 'Oswald', 'size': 15, 'weight': 600},
  },
};

void main() {
  late ProjectAnalysis analysis;
  setUpAll(() async {
    analysis = await FlutterProjectAnalyzer('example').analyze();
  });

  IrDesignSystem system(Map<String, Object?>? theme) => FlutterCompiler(
    iconFonts: projectIconFonts(analysis.root),
  ).compile(analysis, renderedTheme: theme).designSystem!;

  IrColor primary(IrDesignSystem ds, String mode) => ds.colors
      .singleWhere((c) => c.name == 'ColorScheme/primary')
      .values[mode]!;

  test('the mode Flutter rendered takes its colors and text styles', () {
    final ds = system(rendered());
    expect(primary(ds, 'Light').toHex(), '#AD8B73');
    // The code found the app's dark theme: that mode stays as it reads.
    expect(ds.modes, ['Light', 'Dark']);
    expect(primary(ds, 'Dark').toHex(), primary(system(null), 'Dark').toHex());
    final body = ds.textStyles.singleWhere(
      (t) => t.name == 'TextTheme/bodyMedium',
    );
    expect(body.style.fontFamily, 'Oswald');
    expect(body.style.fontWeight, 600);
  });

  test('a dark render sets the Dark mode, and is the active one', () {
    final ds = system(rendered(brightness: 'dark'));
    expect(primary(ds, 'Dark').toHex(), '#AD8B73');
    expect(ds.activeMode, 'Dark');
  });
}
