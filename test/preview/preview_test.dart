import 'dart:convert';
import 'dart:io';

import 'package:flutter2figma/src/preview/preview.dart';
import 'package:test/test.dart';

Map<String, Object?> frame(Map<String, Object?> props) => {
  'type': 'FRAME',
  'name': 'Box',
  'layoutMode': 'NONE',
  'layoutSizingHorizontal': 'FIXED',
  'layoutSizingVertical': 'FIXED',
  'width': 100,
  'height': 100,
  'fills': [],
  'children': [],
  ...props,
};

Map<String, Object?> doc(List<Map<String, Object?>> screens) => {
  'screens': screens,
  'images': {},
  'fonts': [],
};

Map<String, Object?> gradient(String type, List<List<num>> transform) => {
  'type': type,
  'gradientTransform': transform,
  'gradientStops': [
    {
      'color': {'r': 1, 'g': 0, 'b': 0, 'a': 1},
      'position': 0,
    },
    {
      'color': {'r': 0, 'g': 0, 'b': 1, 'a': 1},
      'position': 1,
    },
  ],
};

void main() {
  test('every screen of the golden export is drawn', () {
    final design =
        jsonDecode(File('test/goldens/basic.design.json').readAsStringSync())
            as Map<String, Object?>;
    final page = previewPage(design: design, title: 'example');
    for (final s in (design['screens'] as List).cast<Map>()) {
      expect(page, contains('<h2>${s['name']}</h2>'));
    }
    expect(page, isNot(contains('{{')));
    expect(page, contains('display:flex;flex-direction:column;'));
    expect(page, contains("font-family:'f2f-"));
    expect(page, contains('<svg class="n nv"'));
    // Without Flutter's renders there is nothing to wipe against.
    expect(page, contains('aria-label="View" hidden'));
  });

  test('Flutter renders sit beside the export, with a wipe', () {
    final page = previewPage(
      design: doc([
        frame({'name': 'Home'}),
      ]),
      title: 'app',
      screenshots: {
        'Home': [1, 2, 3],
      },
    );
    expect(page, contains('alt="Flutter render of Home"'));
    expect(page, contains('class="wipe-range"'));
    expect(page, contains('<b>1/1</b>'));
  });

  test('gradients are drawn by the page, at the box\'s laid-out size', () {
    final page = previewPage(
      design: doc([
        frame({
          'name': 'S',
          'fills': [
            gradient('GRADIENT_ANGULAR', [
              [1, 0, 0],
              [0, 1, 0],
            ]),
          ],
        }),
      ]),
      title: 'app',
    );
    expect(page, contains('data-bg="[{&quot;gradient&quot;:'));
    expect(page, contains('GRADIENT_ANGULAR'));
    expect(page, contains('function f2fGradient('));
  });

  test('rotated and absolute children keep their place', () {
    final page = previewPage(
      design: doc([
        frame({
          'name': 'S',
          'children': [
            frame({
              'position': {'left': 10, 'top': 20},
              'rotation': 30,
            }),
          ],
        }),
      ]),
      title: 'app',
    );
    expect(
      page,
      contains(
        'position:absolute;left:10px;width:100px;top:20px;height:100px;'
        'transform:rotate(30deg);transform-origin:0 0;',
      ),
    );
  });
}
