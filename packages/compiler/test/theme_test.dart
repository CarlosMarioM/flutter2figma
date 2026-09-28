import 'package:flutter2figma_analyzer/flutter2figma_analyzer.dart';
import 'package:flutter2figma_compiler/flutter2figma_compiler.dart';
import 'package:flutter2figma_ir/flutter2figma_ir.dart';
import 'package:test/test.dart';

import 'builders.dart';

IrFrame screenOf(IrDocument doc) => doc.screens.single.root;
IrNode bodyOf(IrDocument doc) => screenOf(doc).children.single;

ObjectValue color(int argb) => v('Color', positional: [lit(argb)]);
ObjectValue themeData(Map<String, DartValue> named) =>
    v('ThemeData', named: named);
CallValue themeOf() =>
    CallValue(ref('Theme'), 'of', positional: [const UnknownValue('context')]);
ObjectValue filled(String label, {DartValue? style}) => w(
  'FilledButton',
  named: {
    'onPressed': const FunctionValue(),
    'child': text(label),
    'style': ?style,
  },
);

void main() {
  test('colorSchemeSeed drives the scheme like ColorScheme.fromSeed', () {
    final doc = compileApp({
      'theme': themeData({'colorSchemeSeed': color(0xFF00696E)}),
    }, filled('Go'));
    final seeded = seedColorScheme(
      0xFF00696E,
      brightness: ThemeBrightness.light,
    );
    expect(screenOf(doc).fill!.toArgb32(), seeded['surface']);
    expect((bodyOf(doc) as IrFrame).fill!.toArgb32(), seeded['primary']);
    expect(doc.diagnostics, isEmpty);
  });

  test('ColorScheme.light fills optional roles like Flutter getters', () {
    final doc = compileApp(
      {
        'theme': themeData({
          'colorScheme': v(
            'ColorScheme',
            ctor: 'light',
            named: {'primary': color(0xFF123456)},
          ),
        }),
      },
      w(
        'Column',
        named: {
          'children': list([
            filled('Go'),
            w('Card', named: {'child': text('x')}),
          ]),
        },
      ),
    );
    final column = bodyOf(doc) as IrFrame;
    expect((column.children[0] as IrFrame).fill!.toHex(), '#123456');
    // Card uses surfaceContainerLow, which falls back to surface (white).
    final card = (column.children[1] as IrFrame).children.single as IrFrame;
    expect(card.fill!.toHex(), '#FFFFFF');
  });

  test('an incomplete ColorScheme is reported and the baseline is used', () {
    final doc = compileApp({
      'theme': themeData({
        'colorScheme': v('ColorScheme', named: {'primary': color(0xFF123456)}),
      }),
    }, filled('Go'));
    expect((bodyOf(doc) as IrFrame).fill!.toHex(), '#6750A4');
    expect(
      doc.diagnostics.map((d) => d.message),
      contains(startsWith('Could not evaluate ThemeData.colorScheme')),
    );
  });

  test('themeMode: ThemeMode.dark selects darkTheme', () {
    final app = {
      'theme': themeData({'colorSchemeSeed': color(0xFF00696E)}),
      'darkTheme': themeData({
        'colorSchemeSeed': color(0xFF00696E),
        'brightness': ref('Brightness.dark'),
      }),
      'themeMode': ref('ThemeMode.dark'),
    };
    final dark = seedColorScheme(0xFF00696E, brightness: ThemeBrightness.dark);
    expect(
      screenOf(compileApp(app, text('x'))).fill!.toArgb32(),
      dark['surface'],
    );
    // An explicit brightness wins over themeMode.
    final light = seedColorScheme(
      0xFF00696E,
      brightness: ThemeBrightness.light,
    );
    expect(
      screenOf(
        compileApp(app, text('x'), brightness: ThemeBrightness.light),
      ).fill!.toArgb32(),
      light['surface'],
    );
  });

  test('font family and text theme overrides', () {
    final doc = compileApp({
      'theme': themeData({
        'fontFamily': lit('Inter'),
        'textTheme': v(
          'TextTheme',
          named: {
            'bodyMedium': v('TextStyle', named: {'fontSize': lit(15)}),
          },
        ),
      }),
    }, text('Body'));
    final t = bodyOf(doc) as IrText;
    expect(t.style.fontFamily, 'Inter');
    expect(t.style.fontSize, 15);
    expect(t.style.letterSpacing, 0.25); // Kept from the M3 geometry.
  });

  test('GoogleFonts text themes and styles', () {
    final doc = compileApp(
      {
        'theme': themeData({
          'textTheme': CallValue(ref('GoogleFonts'), 'robotoMonoTextTheme'),
        }),
      },
      w(
        'Column',
        named: {
          'children': list([
            text('a'),
            text(
              'b',
              style: CallValue(
                ref('GoogleFonts'),
                'lobster',
                named: {'fontSize': lit(20)},
              ),
            ),
          ]),
        },
      ),
    );
    final [a, b] = (bodyOf(doc) as IrFrame).children.cast<IrText>();
    expect(a.style.fontFamily, 'Roboto Mono');
    expect(b.style.fontFamily, 'Lobster');
    expect(b.style.fontSize, 20);
  });

  test('component themes: app bar, card, scaffold', () {
    final doc = FlutterCompiler().compile(
      ProjectAnalysis(
        name: 'test',
        root: '.',
        files: const [],
        diagnostics: const [],
        widgets: [
          WidgetClass(
            name: 'App',
            source: 'lib/app.dart:1',
            tree: w(
              'MaterialApp',
              named: {
                'theme': themeData({
                  'scaffoldBackgroundColor': color(0xFFFAFAFA),
                  'appBarTheme': v(
                    'AppBarThemeData',
                    named: {
                      'backgroundColor': color(0xFF222222),
                      'foregroundColor': color(0xFFFFFFFF),
                      'centerTitle': lit(true),
                    },
                  ),
                  'cardTheme': v(
                    'CardThemeData',
                    named: {
                      'elevation': lit(0),
                      'margin': v('EdgeInsets', ctor: 'zero'),
                    },
                  ),
                }),
              },
            ),
          ),
          WidgetClass(
            name: 'Home',
            source: 'lib/home.dart:1',
            tree: w(
              'Scaffold',
              named: {
                'appBar': w('AppBar', named: {'title': text('Inbox')}),
                'body': w('Card', named: {'child': text('x')}),
              },
            ),
          ),
        ],
      ),
    );
    final root = doc.screens.single.root;
    expect(root.fill!.toHex(), '#FAFAFA');
    final appBar = root.children[0] as IrFrame;
    expect(appBar.fill!.toHex(), '#222222');
    final title = appBar.children.single as IrText;
    expect(title.style.color.toHex(), '#FFFFFF');
    expect(title.align, IrTextAlign.center);
    final card = root.children[1] as IrFrame;
    expect(card.name, 'Card');
    expect(card.shadows, isEmpty);
    expect(card.padding.isZero, isTrue, reason: 'margin: EdgeInsets.zero');
  });

  test('button themes apply under the widget style', () {
    final doc = compileApp(
      {
        'theme': themeData({
          'filledButtonTheme': v(
            'FilledButtonThemeData',
            named: {
              'style': CallValue(
                ref('FilledButton'),
                'styleFrom',
                named: {
                  'backgroundColor': color(0xFFAA0000),
                  'foregroundColor': color(0xFF00AA00),
                },
              ),
            },
          ),
        }),
      },
      filled(
        'Go',
        style: CallValue(
          ref('FilledButton'),
          'styleFrom',
          named: {'foregroundColor': color(0xFF0000AA)},
        ),
      ),
    );
    final button = bodyOf(doc) as IrFrame;
    expect(button.fill!.toHex(), '#AA0000'); // theme
    expect(
      (button.children.single as IrText).style.color.toHex(),
      '#0000AA',
    ); // widget
  });

  test('Theme widget scopes a derived theme to its subtree', () {
    final nested = CallValue(
      themeOf(),
      'copyWith',
      named: {
        'colorScheme': CallValue(
          AccessValue(themeOf(), 'colorScheme'),
          'copyWith',
          named: {'primary': color(0xFF00AA00)},
        ),
      },
    );
    final doc = compileApp(
      {},
      w(
        'Column',
        named: {
          'children': list([
            filled('outer'),
            w('Theme', named: {'data': nested, 'child': filled('inner')}),
          ]),
        },
      ),
    );
    final [outer, inner] = (bodyOf(doc) as IrFrame).children.cast<IrFrame>();
    expect(outer.fill!.toHex(), '#6750A4');
    expect(inner.fill!.toHex(), '#00AA00');
    expect(inner.origin.first, 'Theme');
  });

  test('ThemeData.copyWith on an app theme', () {
    final doc = compileApp({
      'theme': CallValue(
        themeData({'colorSchemeSeed': color(0xFF00696E)}),
        'copyWith',
        named: {'scaffoldBackgroundColor': color(0xFFFFFFFF)},
      ),
    }, filled('Go'));
    expect(screenOf(doc).fill!.toHex(), '#FFFFFF');
    expect((bodyOf(doc) as IrFrame).fill!.toHex(), '#00696E');
  });

  test('reports what it cannot apply', () {
    final doc = compileApp({
      'theme': themeData({
        'useMaterial3': lit(false),
        'inputDecorationTheme': v('InputDecorationThemeData'),
      }),
    }, text('x'));
    final messages = doc.diagnostics.map((d) => d.message);
    expect(messages, contains(startsWith('Material 2 themes')));
    expect(
      messages,
      contains('ThemeData arguments not applied: inputDecorationTheme'),
    );
  });
}
