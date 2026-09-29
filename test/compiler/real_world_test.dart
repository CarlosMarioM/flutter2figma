import 'package:flutter2figma/analyzer.dart';
import 'package:flutter2figma/ir.dart';
import 'package:test/test.dart';

import 'builders.dart';

/// Regressions from running against real apps (flutter_bloc screens,
/// animated widgets, full-width buttons, loops, loading gates).

ObjectValue pkg(String type, {Map<String, DartValue> named = const {}}) =>
    ObjectValue(
      type: type,
      library: 'package:flutter_bloc/src/$type.dart',
      isWidget: true,
      named: named,
    );

IrNode bodyOf(IrDocument doc) => doc.screens.single.root.children.single;
List<String> messages(IrDocument doc) => [
  for (final d in doc.diagnostics) d.message,
];

void main() {
  group('package widgets', () {
    test('builder widgets render their builder', () {
      final doc = compileApp(
        {},
        pkg(
          'BlocBuilder',
          named: {'builder': FunctionValue(returns: text('Loaded'))},
        ),
      );
      final node = bodyOf(doc);
      expect(node, isA<IrText>());
      expect(node.origin, ['BlocBuilder', 'Text']);
      expect(
        doc.diagnostics.single.severity,
        IrSeverity.info,
        reason: messages(doc).join(),
      );
    });

    test('providers pass through to their child, as info', () {
      final doc = compileApp(
        {},
        pkg('BlocProvider', named: {'child': text('x')}),
      );
      expect(bodyOf(doc).name, 'x');
      expect(doc.diagnostics.single.severity, IrSeverity.info);
    });

    test('package widgets with nothing to show are flagged', () {
      final doc = compileApp({}, pkg('RTCVideoView'));
      expect(bodyOf(doc).name, '⚠ RTCVideoView');
      expect(doc.diagnostics.single.severity, IrSeverity.warning);
    });
  });

  test('conditionals export the richer branch', () {
    final spinner = w(
      'Center',
      named: {'child': w('CircularProgressIndicator')},
    );
    final content = column([text('a'), text('b'), text('c')]);
    for (final (then, otherwise, expected) in [
      (spinner, content, 'Column'),
      (content, spinner, 'Column'),
    ]) {
      final doc = compileApp({}, ConditionalValue('state', then, otherwise));
      expect(bodyOf(doc).name, expected);
    }
  });

  test('loops over runtime data repeat sample items', () {
    final doc = compileApp(
      {},
      column([
        text('header'),
        LoopValue('final song in songs', text('song')),
        CallValue(
          CallValue(
            const UnknownValue('items'),
            'map',
            positional: [FunctionValue(returns: text('item'))],
          ),
          'toList',
        ),
      ]),
    );
    final names = (bodyOf(doc) as IrFrame).children.map((c) => c.name);
    expect(names, [
      'header',
      ...List.filled(3, 'song'),
      ...List.filled(3, 'item'),
    ]);
  });

  test('Size(double.infinity, h) buttons fill the width', () {
    final doc = compileApp(
      {},
      column([
        w(
          'FilledButton',
          named: {
            'onPressed': const FunctionValue(),
            'child': text('Save'),
            'style': CallValue(
              ref('FilledButton'),
              'styleFrom',
              named: {
                'minimumSize': v(
                  'Size',
                  positional: [ref('double.infinity'), lit(52)],
                ),
              },
            ),
          },
        ),
      ]),
    );
    final button = (bodyOf(doc) as IrFrame).children.single as IrFrame;
    expect(button.width, const IrSizing.fill());
    expect(button.minWidth, 64);
    expect(button.minHeight, 52);
  });

  test('non-finite sizes never reach the output', () {
    final doc = compileApp(
      {},
      w(
        'Container',
        named: {
          'constraints': v(
            'BoxConstraints',
            named: {'minHeight': ref('double.infinity')},
          ),
          'child': text('x'),
        },
      ),
    );
    final container = bodyOf(doc) as IrFrame;
    expect(container.minHeight, isNull);
    expect(messages(doc), contains(startsWith('Non-finite minHeight')));
  });

  test('animated widgets use the static handlers or pass through', () {
    final doc = compileApp(
      {},
      column([
        w(
          'AnimatedContainer',
          named: {
            'color': v('Color', positional: [lit(0xFFFF0000)]),
          },
        ),
        w('FadeTransition', named: {'child': text('faded')}),
      ]),
    );
    final [box, faded] = (bodyOf(doc) as IrFrame).children;
    expect((box as IrFrame).fill!.toHex(), '#FF0000');
    expect(faded.origin, ['FadeTransition', 'Text']);
    expect(
      doc.diagnostics.where((d) => d.severity != IrSeverity.info),
      isEmpty,
    );
  });

  group('inputs and progress', () {
    test('outlined text field shows its label', () {
      final doc = compileApp(
        {},
        w(
          'TextField',
          named: {
            'decoration': v(
              'InputDecoration',
              named: {
                'labelText': lit('Email'),
                'border': v('OutlineInputBorder'),
              },
            ),
          },
        ),
      );
      final field = bodyOf(doc) as IrFrame;
      expect(field.role, 'text-field');
      expect(field.width, const IrSizing.fill());
      expect(field.minHeight, 56);
      expect(field.stroke!.color.token, 'ColorScheme/outline');
      expect(field.corners.topLeft, 4);
      final label = field.children.single as IrText;
      expect(label.text, 'Email');
      expect(label.style.color.token, 'ColorScheme/onSurfaceVariant');
    });

    test('default text field has an underline', () {
      final doc = compileApp({}, w('TextField'));
      final field = bodyOf(doc) as IrFrame;
      expect(field.children.map((c) => c.name), ['Input', 'Underline']);
    });

    test('progress indicators', () {
      final doc = compileApp(
        {},
        column([w('CircularProgressIndicator'), w('LinearProgressIndicator')]),
      );
      final [circle, bar] = (bodyOf(doc) as IrFrame).children.cast<IrFrame>();
      expect(circle.width, const IrSizing.fixed(36));
      expect(circle.stroke!.width, 4);
      expect(circle.stroke!.color.token, 'ColorScheme/primary');
      expect(bar.fill!.token, 'ColorScheme/secondaryContainer');
      expect(bar.height, const IrSizing.fixed(4));
    });
  });

  group('from tic_tac_toe', () {
    test('selection controls follow their known value', () {
      final doc = compileApp(
        {},
        column([
          w('Switch', ctor: 'adaptive', named: {'value': lit(false)}),
          w('Switch', named: {'value': lit(true)}),
          w('Checkbox', named: {'value': lit(true)}),
          w('Radio', named: {'value': lit(1), 'groupValue': lit(1)}),
        ]),
      );
      final [off, on, checkbox, radio] = (bodyOf(doc) as IrFrame).children
          .cast<IrFrame>();
      expect(off.mainAlign, IrMainAlign.start);
      expect(off.fill!.token, 'ColorScheme/surfaceContainerHighest');
      expect(on.mainAlign, IrMainAlign.end);
      expect(on.fill!.token, 'ColorScheme/primary');
      expect(
        (checkbox.children.single as IrFrame).fill!.token,
        'ColorScheme/primary',
      );
      expect((radio.children.single as IrFrame).children, hasLength(1));
    });

    test('unknown switch state is drawn off, with a note', () {
      final doc = compileApp(
        {},
        w('Switch', named: {'value': const UnknownValue('state.on')}),
      );
      expect((bodyOf(doc) as IrFrame).mainAlign, IrMainAlign.start);
      expect(messages(doc), contains(contains('is runtime state')));
    });

    test('grids become rows of equal cells', () {
      final doc = compileApp(
        {},
        w(
          'GridView',
          ctor: 'count',
          named: {
            'crossAxisCount': lit(3),
            'mainAxisSpacing': lit(8),
            'children': list([for (var i = 0; i < 7; i++) text('$i')]),
          },
        ),
      );
      final grid = bodyOf(doc) as IrFrame;
      expect(grid.role, 'grid');
      expect(grid.gap, 8);
      expect(grid.children, hasLength(3)); // 3 + 3 + 1
      final lastRow = grid.children.last as IrFrame;
      expect(lastRow.children, hasLength(3), reason: 'padded with empty cells');
      expect((lastRow.children[1] as IrFrame).children, isEmpty);
      expect(
        (lastRow.children.first as IrFrame).height,
        const IrSizing.fixed(130),
        reason: '390 / 3',
      );
    });

    test('GridView.builder renders itemCount cells', () {
      final doc = compileApp(
        {},
        w(
          'GridView',
          ctor: 'builder',
          named: {
            'gridDelegate': v(
              'SliverGridDelegateWithFixedCrossAxisCount',
              named: {'crossAxisCount': lit(3)},
            ),
            'itemCount': lit(9),
            'itemBuilder': FunctionValue(returns: text('cell')),
          },
        ),
      );
      expect((bodyOf(doc) as IrFrame).children, hasLength(3));
    });

    test('Expanded behind a package widget still fills its Column', () {
      final doc = compileApp(
        {},
        column([
          text('header'),
          pkg(
            'BlocBuilder',
            named: {
              'builder': FunctionValue(
                returns: w('Expanded', named: {'child': text('grid')}),
              ),
            },
          ),
        ]),
      );
      final grid = (bodyOf(doc) as IrFrame).children.last;
      expect(grid.height, const IrSizing.fill());
      expect(messages(doc), isNot(contains(contains('outside of a Row'))));
    });

    test('field reads on known project objects resolve', () {
      final state = ObjectValue(
        type: 'GameState',
        library: 'package:app/state.dart',
        inProject: true,
        named: {'title': lit('Round 1')},
      );
      final doc = compileApp(
        {},
        w('Text', positional: [AccessValue(state, 'title')]),
      );
      expect((bodyOf(doc) as IrText).text, 'Round 1');
    });

    test('an unevaluable theme seed is reported, not silently replaced', () {
      final doc = compileApp({
        'theme': v(
          'ThemeData',
          named: {
            'colorSchemeSeed': AccessValue(
              const UnknownValue('state'),
              'color',
            ),
          },
        ),
      }, text('x'));
      expect(
        messages(doc),
        contains(startsWith('Could not evaluate ThemeData.colorSchemeSeed')),
      );
    });
  });
}

ObjectValue column(List<DartValue> children) =>
    w('Column', named: {'children': list(children)});
