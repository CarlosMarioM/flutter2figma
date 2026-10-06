@Timeout(Duration(minutes: 5))
library;

import 'package:flutter2figma/flutter2figma.dart';
import 'package:flutter2figma/ir.dart';
import 'package:test/test.dart';

/// Renders the showcase's PaintersScreen with Flutter (needs its
/// `flutter pub get`): custom painting, transforms and effects.
void main() {
  late IrFrame root;

  setUpAll(() async {
    final result = await exportProject('showcase', runtime: true);
    root = result.ir.screens
        .singleWhere((s) => s.name == 'PaintersScreen')
        .root;
  });

  Iterable<IrNode> all(IrNode n) sync* {
    yield n;
    if (n is IrFrame) {
      for (final c in n.children) {
        yield* all(c);
      }
    }
  }

  IrFrame wheel() => all(root).whereType<IrFrame>().singleWhere(
    (f) => f.children.whereType<IrVector>().any((v) => v.name == 'Arc'),
  );

  test('the painter turns with its Transform.rotate', () {
    expect(wheel().rotation, closeTo(-36, 0.01));
    expect([wheel().width.value, wheel().height.value], [300, 300]);
  });

  test('shapes become vectors: gradient arcs, a stroked rim, a path', () {
    final shapes = wheel().children.whereType<IrVector>().toList();
    final arcs = shapes.where((v) => v.name == 'Arc').toList();
    expect(arcs, hasLength(4));
    for (final arc in arcs) {
      // The radial gradient fills the wedge as an image.
      expect(arc.image, isNotNull);
      expect(arc.path, startsWith('M '));
      expect(arc.path, contains(' C '));
    }
    final rim = shapes.singleWhere((v) => v.stroke != null);
    expect(rim.stroke!.width, 4);
    expect(rim.fill, isNull);
    expect([rim.width.value, rim.height.value], [280, 280]);
    // The pointer: a traced triangle keeps exactly its three corners.
    final pointer = shapes.singleWhere((v) => v.name == 'Path');
    expect(pointer.path, 'M 0 0 L 24 0 L 12 24 Z');
    expect(pointer.position!.left, closeTo(138, 0.01));
  });

  test('text, blur and shadows a vector can\'t show are images', () {
    final images = wheel().children.whereType<IrFrame>().where(
      (f) => f.image != null,
    );
    final labels = images.where((f) => f.name == 'Text').toList();
    expect(labels, hasLength(4));
    // Each label is drawn upright and turned to its wedge.
    expect(
      labels.map((l) => l.rotation),
      containsAll([closeTo(45, 0.01), closeTo(135, 0.01)]),
    );
    expect(images.map((f) => f.name), containsAll(['Circle', 'Shadow']));
  });

  test('sweep gradients and backdrop blurs carry over', () {
    final frames = all(root).whereType<IrFrame>();
    expect(frames.any((f) => f.gradient?.sweep ?? false), isTrue);
    expect(frames.any((f) => f.backgroundBlur == 24), isTrue);
  });
}
