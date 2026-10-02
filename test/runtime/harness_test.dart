import 'package:flutter2figma/src/runtime/harness.dart';
import 'package:test/test.dart';

void main() {
  test('fills every placeholder', () {
    final source = harnessSource(
      mainImport: 'package:app/main.dart',
      screenImports: {'package:app/home.dart': 's0'},
      screens: {'Home': "s0.Home(title: 'title')"},
      setupImports: ["import '../../test/flutter2figma_setup.dart' as user;"],
      setup: ['  await user.setUp();'],
      wrap: 'user.wrapScreen(name, screen)',
      build: 'user.buildScreen(name) ?? fallback()',
      nested: true,
    );
    expect(source, isNot(contains('/*')));
    expect(source, contains("import 'package:app/main.dart' as app;"));
    expect(source, contains("'Home': () => s0.Home(title: 'title'),"));
    expect(source, contains('await user.setUp();'));
    expect(source, contains('=> user.wrapScreen(name, screen);'));
    expect(source, contains("import 'package:nested/nested.dart' as nested;"));
  });

  test('without nested, providers are not carried over', () {
    final source = harnessSource(
      mainImport: 'package:app/main.dart',
      screenImports: const {},
      screens: const {},
    );
    expect(source, isNot(contains('nested.')));
    expect(source, contains('List<f.Widget> _routeProviders() => const [];'));
  });
}
