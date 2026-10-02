import 'dart:convert';

import 'package:flutter2figma/ir.dart';
import 'package:flutter2figma/src/compiler/icon_font.dart';
import 'package:flutter2figma/src/runtime/capture_converter.dart';
import 'package:flutter2figma/src/runtime/runtime_capture.dart';
import 'package:test/test.dart';

/// A 1×1 PNG header is enough for the converter (it reads the size).
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwnwEJ'
  'AAAA//8DAP0D/wSpA94AAAAASUVORK5CYII=',
);

Map<String, Object?> node(
  String type,
  List<num> rect, [
  Map<String, Object?> props = const {},
]) => {'type': type, 'name': type, 'rect': rect, ...props};

CapturedScreen screen(List<Map<String, Object?>> tree) => CapturedScreen(
  name: 'Home',
  width: 390,
  height: 844,
  tree: tree,
  images: {'img0': png},
  theme: {
    'colorScheme': {'primary': '#ff6750a4', 'onSurface': '#ff1d1b20'},
    'textTheme': {
      'bodyLarge': {
        'family': 'Roboto',
        'size': 16,
        'weight': 400,
        'height': 1.5,
        'letterSpacing': 0.5,
      },
    },
  },
);

void main() {
  final fonts = projectIconFonts('example');

  IrFrame convert(List<Map<String, Object?>> tree, [CaptureConverter? c]) =>
      (c ?? CaptureConverter(iconFonts: fonts)).convert(screen(tree)).root;

  test('boxes keep their place, paint and theme tokens', () {
    final root = convert([
      node(
        'box',
        [20, 30, 100, 40],
        {
          'fill': '#ff6750a4',
          'radius': 8,
          'stroke': {'color': '#ff1d1b20', 'width': 2},
          'elevation': 1,
          'shadowColor': '#ff000000',
          'children': [
            node('box', [30, 35, 10, 10], {'fill': '#611d1b20'}),
          ],
        },
      ),
    ]);
    expect(root.direction, IrLayoutDirection.stack);
    expect(
      [root.width, root.height],
      [const IrSizing.fixed(390), const IrSizing.fixed(844)],
    );
    final box = root.children.single as IrFrame;
    expect([box.position!.left, box.position!.top], [20, 30]);
    expect(box.fill!.token, 'ColorScheme/primary');
    expect(box.corners.topLeft, 8);
    expect(box.stroke!.color.token, 'ColorScheme/onSurface');
    expect(box.shadows, isNotEmpty);
    // Positions are relative to the parent; a translucent role color keeps
    // its token and alpha.
    final inner = box.children.single as IrFrame;
    expect([inner.position!.left, inner.position!.top], [10, 5]);
    expect(inner.fill!.token, 'ColorScheme/onSurface');
    expect(inner.fill!.a, closeTo(0x61 / 255, 0.01));
  });

  test('text keeps Flutter\'s width and binds its text style', () {
    final root = convert([
      node(
        'text',
        [16, 100, 200.4, 24],
        {
          'text': 'Hello',
          'style': {
            'family': 'Roboto',
            'size': 16,
            'weight': 400,
            'height': 1.5,
            'letterSpacing': 0.5,
            'color': '#ff1d1b20',
          },
          'align': 'center',
        },
      ),
    ]);
    final text = root.children.single as IrText;
    expect(text.text, 'Hello');
    expect(text.width, const IrSizing.fixed(200.9));
    expect(text.align, IrTextAlign.center);
    expect(text.style.token, 'TextTheme/bodyLarge');
    expect(text.style.lineHeight, 24);
    expect(text.style.color.token, 'ColorScheme/onSurface');
  });

  test('icons become vectors; images are embedded', () {
    final converter = CaptureConverter(iconFonts: fonts);
    final root = convert([
      node(
        'icon',
        [0, 0, 24, 24],
        {
          'family': 'MaterialIcons',
          'codePoint': 0xe047,
          'size': 24,
          'color': '#ff6750a4',
        },
      ),
      node('image', [0, 50, 100, 60], {'image': 'img0', 'fit': 'cover'}),
      node('image', [0, 50, 100, 60], {'image': 'missing'}),
    ], converter);
    final icon = root.children[0] as IrFrame;
    final glyph = icon.children.single as IrVector;
    expect(glyph.fill.token, 'ColorScheme/primary');
    expect(glyph.position!.left, closeTo(5, 0.05));
    final image = root.children[1] as IrFrame;
    expect(image.image!.fit, IrBoxFit.cover);
    expect(converter.images.keys, ['runtime/Home/img0.png']);
    expect(root.children, hasLength(2), reason: 'missing images are dropped');
  });

  test('groups: single-child groups flatten, opacity and clips apply', () {
    final root = convert([
      node(
        'group',
        [10, 10, 100, 100],
        {
          'children': [
            node('box', [20, 20, 10, 10], {'fill': '#ff6750a4'}),
          ],
        },
      ),
      node(
        'group',
        [0, 200, 100, 100],
        {
          'clip': true,
          'radius': 12,
          'opacity': 0.5,
          'children': [
            node('box', [0, 200, 10, 10], {'fill': '#ff6750a4'}),
          ],
        },
      ),
    ]);
    final flattened = root.children[0] as IrFrame;
    expect(flattened.fill!.token, 'ColorScheme/primary');
    expect([flattened.position!.left, flattened.position!.top], [20, 20]);
    final clip = root.children[1] as IrFrame;
    expect(clip.clip, isTrue);
    expect(clip.corners.topLeft, 12);
    expect((clip.children.single as IrFrame).fill!.a, closeTo(0.5, 0.01));
  });

  test('a one-sided border becomes a line on that edge', () {
    final box =
        convert([
              node(
                'box',
                [0, 0, 200, 50],
                {
                  'stroke': {
                    'color': '#ff1d1b20',
                    'width': 1,
                    'side': 'bottom',
                  },
                },
              ),
            ]).children.single
            as IrFrame;
    expect(box.stroke, isNull);
    final line = box.children.single as IrFrame;
    expect([line.position!.top, line.height], [49, const IrSizing.fixed(1)]);
  });
}
