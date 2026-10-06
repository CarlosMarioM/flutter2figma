import 'package:flutter2figma/ir.dart';
import 'package:flutter2figma/src/runtime/capture_converter.dart';
import 'package:flutter2figma/src/runtime/runtime_capture.dart';
import 'package:test/test.dart';

Map<String, Object?> box(
  List<num> rect, [
  List<Map<String, Object?>> children = const [],
  Map<String, Object?> props = const {},
]) => {
  'type': 'box',
  'name': 'Box',
  'rect': rect,
  'fill': '#ffeeeeee',
  'children': children,
  ...props,
};

Map<String, Object?> text(String s, List<num> rect) => {
  'type': 'text',
  'name': 'Text',
  'rect': rect,
  'text': s,
  'style': {'size': 14, 'height': 1.43, 'color': '#ff000000'},
};

/// The root's single child (a card) after conversion.
IrFrame convert(Map<String, Object?> card) {
  final root = CaptureConverter()
      .convert(
        CapturedScreen(
          name: 'S',
          width: 390,
          height: 844,
          tree: [card],
          theme: const {},
          images: const {},
        ),
      )
      .root;
  return root.children.single as IrFrame;
}

void main() {
  test('a padded column of full-width children', () {
    final card = convert(
      box(
        [0, 0, 390, 112],
        [
          text('One', [16, 16, 358, 20]),
          text('Two', [16, 44, 358, 20]),
          text('Three', [16, 72, 358, 20]),
        ],
      ),
    );
    expect(card.direction, IrLayoutDirection.vertical);
    expect(card.gap, 8);
    expect(
      [
        card.padding.top,
        card.padding.left,
        card.padding.right,
        card.padding.bottom,
      ],
      [16, 16, 16, 20],
    );
    expect(card.crossAlign, IrCrossAlign.start);
    for (final c in card.children) {
      expect(c.position, isNull);
      expect(c.width, const IrSizing.fill(), reason: 'spans the padded width');
    }
  });

  test('larger spaces become spacers, the smallest is the gap', () {
    final card = convert(
      box(
        [0, 0, 200, 100],
        [
          text('A', [0, 0, 100, 20]),
          text('B', [0, 28, 100, 20]),
          text('C', [0, 72, 100, 20]),
        ],
      ),
    );
    expect(card.gap, 8);
    expect(card.children.map((c) => c.name), ['A', 'B', 'Spacer', 'C']);
    // 24 = gap 8 + spacer 8 + gap 8.
    expect(card.children[2].height, const IrSizing.fixed(8));
  });

  test('a row with an Expanded child fills the main axis', () {
    final row = convert({
      'type': 'group',
      'name': 'Row',
      'flex': 'horizontal',
      'rect': [0, 0, 390, 48],
      'children': [
        box([16, 12, 24, 24]),
        {
          ...text('Title', [56, 14, 270, 20]),
          'flexFactor': 1,
        },
        box([342, 12, 24, 24]),
      ],
    });
    expect(row.direction, IrLayoutDirection.horizontal);
    expect(row.gap, 16);
    expect([row.padding.left, row.padding.right], [16, 24]);
    expect(row.crossAlign, IrCrossAlign.center);
    expect(row.children[1].width, const IrSizing.fill());
    expect(row.children.first.width, const IrSizing.fixed(24));
  });

  test('a background takes in the content painted on it', () {
    final card = convert(
      box(
        [0, 0, 200, 200],
        [
          box([0, 0, 200, 120]),
          text('Over', [20, 20, 100, 20]),
        ],
      ),
    );
    // The text moved into the box it sits on, which lays it out.
    final background = card.children.single as IrFrame;
    final over = background.children.single;
    expect(over.name, 'Over');
    expect(background.direction, IrLayoutDirection.vertical);
    expect([background.padding.left, background.padding.top], [20, 20]);
  });

  test('truly overlapping children stay absolute', () {
    final stack = convert(
      box(
        [0, 0, 200, 200],
        [
          box([0, 0, 120, 120]),
          box([60, 60, 120, 120]),
        ],
      ),
    );
    expect(stack.direction, IrLayoutDirection.stack);
    expect(stack.children.every((c) => c.position != null), isTrue);
  });

  test('a child off the shared alignment is absolute inside the flow', () {
    final card = convert(
      box(
        [0, 0, 300, 120],
        [
          text('One', [16, 16, 100, 20]),
          text('Two', [16, 44, 100, 20]),
          text('Badge', [250, 80, 40, 20]),
        ],
      ),
    );
    expect(card.direction, IrLayoutDirection.vertical);
    final badge = card.children.firstWhere((c) => c.name == 'Badge');
    expect([badge.position!.left, badge.position!.top], [250, 80]);
    expect(card.children.where((c) => c.position == null), hasLength(2));
  });
}
