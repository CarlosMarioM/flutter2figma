import 'package:flutter2figma_analyzer/flutter2figma_analyzer.dart';
import 'package:flutter2figma_compiler/flutter2figma_compiler.dart';
import 'package:flutter2figma_ir/flutter2figma_ir.dart';
import 'package:test/test.dart';

// Builders for analyzer output, so compiler tests don't need a Flutter SDK.

ObjectValue w(
  String type, {
  String? ctor,
  Map<String, DartValue> named = const {},
  List<DartValue> positional = const [],
}) => ObjectValue(
  type: type,
  constructor: ctor,
  library: 'package:flutter/src/widgets/$type.dart',
  isWidget: true,
  named: named,
  positional: positional,
);

ObjectValue v(
  String type, {
  String? ctor,
  Map<String, DartValue> named = const {},
  List<DartValue> positional = const [],
}) => ObjectValue(
  type: type,
  constructor: ctor,
  library: 'package:flutter/src/painting/$type.dart',
  named: named,
  positional: positional,
);

LiteralValue lit(Object? value) => LiteralValue(value);
RefValue ref(String dotted, {DartValue? constant}) =>
    RefValue(dotted.split('.'), constant: constant);
ListValue list(List<DartValue> items) => ListValue(items);
ObjectValue text(String s, {DartValue? style}) =>
    w('Text', positional: [lit(s)], named: {'style': ?style});
ObjectValue gap(double h) => w('SizedBox', named: {'height': lit(h)});

IrFrame screen(DartValue body, {DartValue? appBar}) {
  final compiler = FlutterCompiler();
  return compiler
      .compileScreen(
        'Test',
        w('Scaffold', named: {'body': body, 'appBar': ?appBar}),
        null,
      )
      .root;
}

IrNode body(DartValue widget) => screen(widget).children.single;

void main() {
  group('the §17 reference screen', () {
    late IrFrame column;

    setUp(() {
      column =
          body(
                w(
                  'Padding',
                  named: {
                    'padding': v(
                      'EdgeInsets',
                      ctor: 'all',
                      positional: [lit(24)],
                    ),
                    'child': w(
                      'Column',
                      named: {
                        'crossAxisAlignment': ref('CrossAxisAlignment.start'),
                        'children': list([
                          text('Welcome'),
                          gap(16),
                          w(
                            'Container',
                            named: {
                              'padding': v(
                                'EdgeInsets',
                                ctor: 'all',
                                positional: [lit(16)],
                              ),
                              'child': text('Hello'),
                            },
                          ),
                          gap(16),
                          w(
                            'ElevatedButton',
                            named: {
                              'onPressed': const FunctionValue(),
                              'child': text('Continue'),
                            },
                          ),
                        ]),
                      },
                    ),
                  },
                ),
              )
              as IrFrame;
    });

    test('folds Padding into the Column and SizedBoxes into a gap', () {
      expect(column.name, 'Column');
      expect(column.origin, ['Padding', 'Column', 'SizedBox']);
      expect(column.padding, const IrInsets.all(24));
      expect(column.gap, 16);
      expect(column.children.map((c) => c.name), [
        'Welcome',
        'Container',
        'ElevatedButton',
      ]);
    });

    test('sizes like Flutter: body fills, Column fills its max main axis', () {
      expect(column.width, const IrSizing.fill());
      expect(column.height, const IrSizing.fill());
      expect(column.crossAlign, IrCrossAlign.start);
      final container = column.children[1] as IrFrame;
      expect(container.width, const IrSizing.hug());
      expect(container.padding, const IrInsets.all(16));
    });

    test('applies Material 3 defaults', () {
      final welcome = column.children.first as IrText;
      expect(welcome.style.fontFamily, 'Roboto');
      expect(welcome.style.fontSize, 14);
      expect(welcome.style.lineHeight, 20.02);
      expect(welcome.style.color.toHex(), '#1D1B20');

      final button = column.children.last as IrFrame;
      expect(button.role, 'button');
      expect(button.fill!.toHex(), '#F7F2FA');
      expect(button.corners.topLeft, 20);
      expect(button.minHeight, 40);
      expect(button.padding, const IrInsets.symmetric(horizontal: 24));
      expect(button.shadows, hasLength(2));
      final label = button.children.single as IrText;
      expect(label.style.fontWeight, 500);
      expect(label.style.color.toHex(), '#6750A4');
    });
  });

  test('uneven spacers stay as spacer frames', () {
    final column =
        body(
              w(
                'Column',
                named: {
                  'children': list([
                    text('a'),
                    gap(8),
                    text('b'),
                    gap(16),
                    text('c'),
                  ]),
                },
              ),
            )
            as IrFrame;
    expect(column.gap, 0);
    expect(column.children.map((c) => c.name), [
      'a',
      'Spacer 8',
      'b',
      'Spacer 16',
      'c',
    ]);
  });

  test('Expanded children fill the Row main axis', () {
    final row =
        body(
              w(
                'Row',
                named: {
                  'children': list([
                    w('Expanded', named: {'child': text('left')}),
                    text('right'),
                  ]),
                },
              ),
            )
            as IrFrame;
    expect(row.direction, IrLayoutDirection.horizontal);
    expect(row.width, const IrSizing.fill());
    expect(row.children[0].width, const IrSizing.fill());
    expect(row.children[0].origin, ['Expanded', 'Text']);
    expect(row.children[1].width, const IrSizing.hug());
  });

  test('stretch forces children to fill the cross axis', () {
    final column =
        body(
              w(
                'Column',
                named: {
                  'crossAxisAlignment': ref('CrossAxisAlignment.stretch'),
                  'children': list([text('a')]),
                },
              ),
            )
            as IrFrame;
    expect(column.crossAlign, IrCrossAlign.start);
    expect(column.children.single.width, const IrSizing.fill());
  });

  test('Center keeps its wrapper so the child stays centered', () {
    final center = body(w('Center', named: {'child': text('hi')})) as IrFrame;
    expect(center.name, 'Center');
    expect(center.mainAlign, IrMainAlign.center);
    expect(center.crossAlign, IrCrossAlign.center);
    expect(center.children.single.width, const IrSizing.hug());
  });

  test('SizedBox with a child folds into a fixed-size child', () {
    final node = body(
      w(
        'SizedBox',
        named: {
          'width': lit(120),
          'height': lit(48),
          'child': w('Container', named: {'color': ref('Colors.red')}),
        },
      ),
    );
    expect(node.name, 'Container');
    expect(node.width, const IrSizing.fixed(120));
    expect(node.height, const IrSizing.fixed(48));
    expect(node.origin, ['SizedBox', 'Container']);
  });

  test('decoration: color, radius, border, shadow, margin', () {
    final node =
        body(
              w(
                'Container',
                named: {
                  'margin': v(
                    'EdgeInsets',
                    ctor: 'symmetric',
                    named: {'horizontal': lit(8)},
                  ),
                  'width': lit(100),
                  'height': lit(50),
                  'decoration': v(
                    'BoxDecoration',
                    named: {
                      'color': v('Color', positional: [lit(0x802196F3)]),
                      'borderRadius': v(
                        'BorderRadius',
                        ctor: 'only',
                        named: {
                          'topLeft': v(
                            'Radius',
                            ctor: 'circular',
                            positional: [lit(8)],
                          ),
                        },
                      ),
                      'border': v(
                        'Border',
                        ctor: 'all',
                        named: {'width': lit(2)},
                      ),
                      'boxShadow': list([
                        v(
                          'BoxShadow',
                          named: {
                            'blurRadius': lit(4),
                            'offset': v('Offset', positional: [lit(0), lit(2)]),
                          },
                        ),
                      ]),
                    },
                  ),
                },
              ),
            )
            as IrFrame;
    expect(node.name, 'Container');
    expect(node.padding, const IrInsets.symmetric(horizontal: 8));
    final box = node.children.single as IrFrame;
    expect(box.fill!.toHex(), '#2196F380');
    expect(box.corners.topLeft, 8);
    expect(box.corners.topRight, 0);
    expect(box.stroke!.width, 2);
    expect(box.shadows.single.y, 2);
    expect(box.shadows.single.blur, 4);
  });

  group('colors', () {
    final blue = ref(
      'Colors.blue',
      constant: v(
        'MaterialColor',
        positional: [
          lit(0xFF2196F3),
          MapValue([
            (lit(200), v('Color', positional: [lit(0xFF90CAF9)])),
          ]),
        ],
      ),
    );

    IrColor? colorOf(DartValue color) {
      final node = body(w('Container', named: {'color': color})) as IrFrame;
      return node.fill;
    }

    test('MaterialColor, shades and opacity', () {
      expect(colorOf(blue)!.toHex(), '#2196F3');
      expect(colorOf(AccessValue(blue, 'shade200'))!.toHex(), '#90CAF9');
      expect(
        colorOf(
          CallValue(blue, 'withValues', named: {'alpha': lit(0.5)}),
        )!.toHex(),
        '#2196F380',
      );
      expect(
        colorOf(
          v(
            'Color',
            ctor: 'fromARGB',
            positional: [lit(255), lit(255), lit(0), lit(0)],
          ),
        )!.toHex(),
        '#FF0000',
      );
    });

    test('theme color scheme lookups', () {
      final scheme = AccessValue(
        AccessValue(CallValue(ref('Theme'), 'of'), 'colorScheme'),
        'primary',
      );
      expect(colorOf(scheme)!.toHex(), '#6750A4');
    });
  });

  test('text styles merge theme, copyWith and explicit values', () {
    final textTheme = AccessValue(CallValue(ref('Theme'), 'of'), 'textTheme');
    final style = CallValue(
      AccessValue(textTheme, 'titleMedium'),
      'copyWith',
      named: {'fontWeight': ref('FontWeight.bold')},
    );
    final t = body(text('Title', style: style)) as IrText;
    expect(t.style.fontSize, 16);
    expect(t.style.fontWeight, 700);
    expect(t.style.letterSpacing, 0.15);
    expect(t.style.lineHeight, 24);
  });

  test('disabled buttons use disabled colors', () {
    final button =
        body(
              w(
                'FilledButton',
                named: {'onPressed': lit(null), 'child': text('Save')},
              ),
            )
            as IrFrame;
    expect(button.name, 'FilledButton (disabled)');
    expect(button.fill!.toHex(), '#1D1B201F');
    expect((button.children.single as IrText).style.color.toHex(), '#1D1B2061');
  });

  test('project widgets are expanded and named after their class', () {
    final custom = ObjectValue(
      type: 'PriceTag',
      library: 'package:app/price_tag.dart',
      isWidget: true,
      build: w(
        'Container',
        named: {
          'color': ref(
            'Colors.black',
            constant: v('Color', positional: [lit(0xFF000000)]),
          ),
          'child': text(r'$9'),
        },
      ),
    );
    final node = body(custom) as IrFrame;
    expect(node.name, 'PriceTag');
    expect(node.origin, ['PriceTag', 'Container']);
  });

  test('unsupported and unresolved widgets become flagged placeholders', () {
    final compiler = FlutterCompiler();
    final root = compiler
        .compileScreen(
          'Test',
          w(
            'Scaffold',
            named: {
              'body': w(
                'Column',
                named: {
                  'children': list([
                    const UnknownValue('buildHeader()'),
                    w('FancyChart'),
                  ]),
                },
              ),
            },
          ),
          null,
        )
        .root;
    final names = (root.children.single as IrFrame).children
        .map((c) => c.name)
        .toList();
    expect(names, ['⚠ Unresolved: buildHeader()', '⚠ FancyChart']);
    expect(compiler.diagnostics.map((d) => d.message), [
      'Could not statically resolve widget `buildHeader()`',
      'Unsupported widget `FancyChart`',
    ]);
  });

  test('conditional UI exports the true branch with a note', () {
    final compiler = FlutterCompiler();
    final root = compiler
        .compileScreen(
          'Test',
          w(
            'Scaffold',
            named: {
              'body': ConditionalValue(
                'loggedIn',
                text('Dashboard'),
                text('Login'),
              ),
            },
          ),
          null,
        )
        .root;
    expect(root.children.single.name, 'Dashboard');
    expect(compiler.diagnostics.single.severity, IrSeverity.info);
  });

  test('ListView.builder renders sample items', () {
    final list =
        body(
              w(
                'ListView',
                ctor: 'builder',
                named: {
                  'itemCount': const UnknownValue('items.length'),
                  'itemBuilder': FunctionValue(
                    returns: w('Card', named: {'child': text('Item')}),
                  ),
                },
              ),
            )
            as IrFrame;
    expect(list.children, hasLength(3));
    expect(list.children.first.name, 'Card #1');
  });

  test('AppBar with actions', () {
    final root = screen(
      w('Center', named: {'child': text('x')}),
      appBar: w(
        'AppBar',
        named: {
          'title': text('Inbox'),
          'actions': list([
            w(
              'IconButton',
              named: {
                'onPressed': const FunctionValue(),
                'icon': w('Icon', positional: [ref('Icons.search')]),
              },
            ),
          ]),
        },
      ),
    );
    final appBar = root.children.first as IrFrame;
    expect(appBar.role, 'app-bar');
    expect(appBar.height, const IrSizing.fixed(64));
    expect(appBar.children.map((c) => c.name), ['Inbox', 'IconButton']);
    final title = appBar.children.first as IrText;
    expect(title.style.fontSize, 22);
    expect(title.width, const IrSizing.fill());
    final icon = (appBar.children.last as IrFrame).children.single;
    expect(icon.name, 'Icon/search');
  });
}
