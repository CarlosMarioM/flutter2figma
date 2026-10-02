@Timeout(Duration(minutes: 5))
library;

import 'package:flutter2figma/flutter2figma.dart';
import 'package:flutter2figma/ir.dart';
import 'package:test/test.dart';

/// Renders the example app with Flutter (needs its `flutter pub get`).
void main() {
  late ExportResult result;

  setUpAll(() async {
    result = await exportProject('example', runtime: true);
  });

  IrFrame screen(String name) =>
      result.ir.screens.singleWhere((s) => s.name == name).root;

  Iterable<IrNode> all(IrNode n) sync* {
    yield n;
    if (n is IrFrame) {
      for (final c in n.children) {
        yield* all(c);
      }
    }
  }

  test('renders every example screen with Flutter', () {
    expect(
      result.ir.diagnostics.map((d) => d.message),
      contains('Runtime: 6 of 6 screens rendered by Flutter'),
    );
    for (final s in result.ir.screens) {
      expect(s.root.origin, ['runtime'], reason: s.name);
    }
  });

  test('records Flutter\'s exact layout and binds the theme', () {
    final contacts = screen('ContactsScreen');
    final nodes = all(contacts).toList();
    final title = nodes.whereType<IrText>().firstWhere(
      (t) => t.text == 'Contacts',
    );
    expect(title.style.token, startsWith('TextTheme/'));

    // The NavigationBar's indicator: an Ink decoration on the Material.
    final indicator = nodes.whereType<IrFrame>().firstWhere(
      (f) =>
          f.fill?.token == 'ColorScheme/secondaryContainer' &&
          f.corners.topLeft == 16,
    );
    expect(
      [indicator.width, indicator.height],
      [const IrSizing.fixed(64), const IrSizing.fixed(32)],
    );
    // Icons are vectors; the switch (a CustomPainter) is an image.
    expect(nodes.whereType<IrVector>(), isNotEmpty);
    expect(
      nodes.whereType<IrFrame>().where((f) => f.image != null),
      isNotEmpty,
    );
  });

  test('asset images are captured', () {
    final profile = all(screen('ProfileScreen')).whereType<IrFrame>();
    expect(
      profile.where((f) => f.image != null),
      hasLength(greaterThanOrEqualTo(2)),
    );
  });
}
