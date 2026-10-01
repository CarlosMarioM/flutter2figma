import 'package:flutter2figma/analyzer.dart';
import 'package:flutter2figma/compiler.dart';
import 'package:flutter2figma/ir.dart';
import 'package:test/test.dart';

import 'builders.dart';

ObjectValue color(int argb) => v('Color', positional: [lit(argb)]);
ObjectValue themeData(Map<String, DartValue> named) =>
    v('ThemeData', named: named);
ObjectValue button(
  String type,
  String label, {
  bool enabled = true,
  DartValue? style,
}) => w(
  type,
  named: {
    'onPressed': enabled ? const FunctionValue() : lit(null),
    'child': text(label),
    'style': ?style,
  },
);

/// A project widget occurrence whose build is [tree].
ObjectValue projectWidget(String name, DartValue tree) => ObjectValue(
  type: name,
  library: 'package:app/widgets.dart',
  isWidget: true,
  build: tree,
);

IrNode bodyOf(IrDocument doc) => doc.screens.single.root.children.single;
List<IrNode> columnChildren(IrDocument doc) =>
    (bodyOf(doc) as IrFrame).children;
ObjectValue column(List<DartValue> children) =>
    w('Column', named: {'children': list(children)});

void main() {
  group('color tokens', () {
    test('theme colors carry their scheme role, alpha kept separately', () {
      final doc = compileApp(
        {},
        column([
          button('FilledButton', 'Go'),
          button('FilledButton', 'No', enabled: false),
        ]),
      );
      final [go, no] = columnChildren(doc).map(unwrap).toList();
      expect(go.fill!.token, 'ColorScheme/primary');
      expect(no.fill!.token, 'ColorScheme/onSurface');
      expect(no.fill!.a, closeTo(0.12, 0.001));
      expect(doc.screens.single.root.fill!.token, 'ColorScheme/surface');
    });

    test('literal colors have no token', () {
      final doc = compileApp(
        {},
        w('Container', named: {'color': color(0xFF123456)}),
      );
      expect((bodyOf(doc) as IrFrame).fill!.token, isNull);
    });

    test('project constants become tokens, if painted', () {
      RefValue constant(String dotted, int argb) =>
          RefValue(dotted.split('.'), resolved: color(argb), inProject: true);
      final doc = compileApp(
        {
          // Used only to build the theme: not a design token.
          'theme': themeData({
            'colorSchemeSeed': constant('AppColors.seed', 0xFF00696E),
          }),
        },
        w(
          'Container',
          named: {'color': constant('AppColors.brand', 0xFFFF5500)},
        ),
      );
      expect((bodyOf(doc) as IrFrame).fill!.token, 'AppColors/brand');
      final names = doc.designSystem!.colors.map((c) => c.name);
      expect(names, contains('AppColors/brand'));
      expect(names, isNot(contains('AppColors/seed')));
    });
  });

  group('text style tokens', () {
    IrTextStyle styleOf(DartValue textWidget) =>
        (bodyOf(compileApp({}, textWidget)) as IrText).style;

    test('inherited theme style keeps its token', () {
      expect(styleOf(text('a')).token, 'TextTheme/bodyMedium');
    });

    test('a typography override drops the token', () {
      final style = v('TextStyle', named: {'fontSize': lit(32)});
      expect(styleOf(text('a', style: style)).token, isNull);
    });

    test('a color-only override keeps the token', () {
      final style = v('TextStyle', named: {'color': color(0xFFFF0000)});
      expect(styleOf(text('a', style: style)).token, 'TextTheme/bodyMedium');
    });

    test('typography identical to another theme style matches it', () {
      // bodyMedium + these values = bodyLarge (16 / 1.5 / 0.5).
      final style = v(
        'TextStyle',
        named: {
          'fontSize': lit(16),
          'height': lit(1.5),
          'letterSpacing': lit(0.5),
        },
      );
      expect(styleOf(text('a', style: style)).token, 'TextTheme/bodyLarge');
    });
  });

  test('elevation shadows reference effect styles', () {
    final doc = compileApp(
      {},
      column([
        button('ElevatedButton', 'Go'),
        w('Card', named: {'elevation': lit(0), 'child': text('x')}),
      ]),
    );
    final [elevatedTarget, card] = columnChildren(doc).cast<IrFrame>();
    final elevated = unwrap(elevatedTarget);
    expect(elevated.shadowToken, 'Elevation/level1');
    expect((card.children.single as IrFrame).shadowToken, isNull);
    expect(doc.designSystem!.shadows.map((s) => s.name), [
      'Elevation/level1',
      'Elevation/level2',
      'Elevation/level3',
      'Elevation/level4',
      'Elevation/level5',
    ]);
  });

  group('components', () {
    test('buttons group by type and state; text differences are overrides', () {
      final doc = compileApp(
        {},
        column([
          button('FilledButton', 'Save'),
          button('FilledButton', 'Send'),
          button('FilledButton', 'Nope', enabled: false),
          button('OutlinedButton', 'Cancel'),
        ]),
      );
      final components = doc.designSystem!.components;
      expect(components.map((c) => c.name), ['Button']);
      final variants = {
        for (final v in components.single.variants) v.props.toString(): v.uses,
      };
      expect(variants, {
        '{Type: Filled, State: Enabled}': 2,
        '{Type: Filled, State: Disabled}': 1,
        '{Type: Outlined, State: Enabled}': 1,
      });
      final [save, send, ..._] = columnChildren(doc).map(unwrap).toList();
      expect(save.instance!.key, send.instance!.key);
    });

    test('visual differences split a variant', () {
      final red = CallValue(
        ref('FilledButton'),
        'styleFrom',
        named: {'backgroundColor': color(0xFFFF0000)},
      );
      final doc = compileApp(
        {},
        column([
          button('FilledButton', 'A'),
          button('FilledButton', 'B', style: red),
        ]),
      );
      final variants = doc.designSystem!.components.single.variants;
      expect(variants.map((v) => v.props['Variant']), ['1', '2']);
    });

    ObjectValue tag(String label) => projectWidget(
      'Tag',
      w(
        'Container',
        named: {
          'color': color(0xFFEEEEEE),
          'padding': v('EdgeInsets', ctor: 'all', positional: [lit(8)]),
          'child': text(label),
        },
      ),
    );

    test('project widgets become components once repeated', () {
      final once = compileApp({}, column([tag('a')]));
      expect(once.designSystem!.components, isEmpty);
      expect(columnChildren(once).single.instance, isNull);

      final twice = compileApp({}, column([tag('a'), tag('b')]));
      final tagComponent = twice.designSystem!.components.single;
      expect(tagComponent.name, 'Tag');
      expect(tagComponent.variants.single.uses, 2);
      expect(tagComponent.variants.single.props, isEmpty);
    });

    test('minComponentUses is configurable', () {
      final doc = compileApp(
        {},
        column([tag('a')]),
        compiler: FlutterCompiler(minComponentUses: 1),
      );
      expect(doc.designSystem!.components.map((c) => c.name), ['Tag']);
    });

    test('outer padding is not folded into a component occurrence', () {
      final doc = compileApp(
        {},
        column([
          w(
            'Padding',
            named: {
              'padding': v('EdgeInsets', ctor: 'all', positional: [lit(4)]),
              'child': tag('a'),
            },
          ),
          tag('b'),
        ]),
      );
      final [padded, plain] = columnChildren(doc).cast<IrFrame>();
      expect(padded.name, 'Padding');
      expect(padded.children.single.instance!.key, plain.instance!.key);
    });
  });

  group('modes', () {
    test('theme and darkTheme become Light and Dark values', () {
      final doc = compileApp({
        'theme': themeData({'colorSchemeSeed': color(0xFF00696E)}),
        'darkTheme': themeData({
          'colorSchemeSeed': color(0xFF00696E),
          'brightness': ref('Brightness.dark'),
        }),
      }, text('x'));
      final ds = doc.designSystem!;
      expect(ds.modes, ['Light', 'Dark']);
      expect(ds.activeMode, 'Light');
      final primary = ds.colors.firstWhere(
        (c) => c.name == 'ColorScheme/primary',
      );
      expect(primary.values['Light']!.toHex(), '#00696E');
      expect(primary.values['Dark']!.toHex(), '#80D4D9');
    });

    test('without darkTheme there is a single mode', () {
      final doc = compileApp({
        'theme': themeData({'colorSchemeSeed': color(0xFF00696E)}),
      }, text('x'));
      expect(doc.designSystem!.modes, ['Light']);
    });

    test('exporting dark marks Dark as the active mode', () {
      final doc = compileApp(
        {
          'theme': themeData({}),
          'darkTheme': themeData({'brightness': ref('Brightness.dark')}),
        },
        text('x'),
        brightness: ThemeBrightness.dark,
      );
      expect(doc.designSystem!.activeMode, 'Dark');
    });
  });

  test('design system can be turned off', () {
    final doc = compileApp(
      {},
      column([button('FilledButton', 'Go')]),
      compiler: FlutterCompiler(designSystem: false),
    );
    expect(doc.designSystem, isNull);
    expect(columnChildren(doc).single.instance, isNull);
  });
}
