import 'package:flutter2figma_analyzer/flutter2figma_analyzer.dart';
import 'package:test/test.dart';

/// Runs against `examples/basic`, which needs `flutter pub get` (via fvm).
void main() {
  late ProjectAnalysis analysis;

  setUpAll(() async {
    analysis = await FlutterProjectAnalyzer('../../examples/basic').analyze();
  });

  WidgetClass widget(String name) =>
      analysis.widgets.singleWhere((w) => w.name == name);

  test('discovers screens and widget classes', () {
    expect(analysis.name, 'basic');
    expect(analysis.diagnostics, isEmpty);
    expect(
      analysis.widgets.map((w) => w.name),
      containsAll(['MainApp', 'HomeScreen', 'ProfileScreen', 'StatCard']),
    );
    expect(
      analysis.screens.map((s) => s.name),
      unorderedEquals(['HomeScreen', 'ProfileScreen']),
    );
    expect(widget('HomeScreen').source, 'lib/home_screen.dart:4');
  });

  test('builds a structured widget tree', () {
    final scaffold = widget('HomeScreen').tree as ObjectValue;
    expect(scaffold.type, 'Scaffold');
    expect(scaffold.isFlutter, isTrue);

    final padding = scaffold['body'] as ObjectValue;
    expect(padding.type, 'Padding');
    final insets = padding['padding'] as ObjectValue;
    expect(insets.displayName, 'EdgeInsets.all');
    expect((insets.arg(0) as LiteralValue).value, 24);

    final column = padding['child'] as ObjectValue;
    final children = (column['children'] as ListValue).items
        .cast<ObjectValue>();
    expect(children.map((c) => c.type), [
      'Text',
      'SizedBox',
      'Container',
      'SizedBox',
      'ElevatedButton',
    ]);
    expect(children.every((c) => c.isWidget), isTrue);
    expect((children[4]['onPressed']), isA<FunctionValue>());
  });

  test('follows constants into the Flutter SDK', () {
    final scaffold = widget('HomeScreen').tree as ObjectValue;
    final column = (scaffold['body'] as ObjectValue)['child'] as ObjectValue;
    final container = (column['children'] as ListValue).items[2] as ObjectValue;
    final color = (container['decoration'] as ObjectValue)['color'] as RefValue;
    expect(color.dotted, 'Colors.blue');
    final swatch = color.resolved as ObjectValue;
    expect(swatch.type, 'MaterialColor');
    final primary = swatch.arg(0) as RefValue;
    expect((primary.resolved as LiteralValue).value, 0xFF2196F3);
  });

  test('inlines project widgets with constructor arguments bound', () {
    final profile = widget('ProfileScreen').tree as ObjectValue;
    final column = (profile['body'] as ObjectValue)['child'] as ObjectValue;
    final row = (column['children'] as ListValue).items[2] as ObjectValue;
    final expanded = (row['children'] as ListValue).items.first as ObjectValue;
    final statCard = expanded['child'] as ObjectValue;
    expect(statCard.type, 'StatCard');
    expect(statCard.isFlutter, isFalse);

    final card = statCard.build as ObjectValue;
    expect(card.type, 'Card');
    final inner = (card['child'] as ObjectValue)['child'] as ObjectValue;
    final texts = (inner['children'] as ListValue).items.cast<ObjectValue>();
    expect(texts.map((t) => (t.arg(0) as LiteralValue).value), [
      '128',
      'Posts',
    ]);
  });

  test('resolves local variables in build', () {
    final profile = widget('ProfileScreen').tree as ObjectValue;
    final column = (profile['body'] as ObjectValue)['child'] as ObjectValue;
    final name = (column['children'] as ListValue).items.first as ObjectValue;
    // `textTheme.headlineMedium` where `final textTheme = Theme.of(context).textTheme;`
    final style = name['style'] as AccessValue;
    expect(style.name, 'headlineMedium');
    final textTheme = style.target as AccessValue;
    expect(textTheme.name, 'textTheme');
    expect((textTheme.target as CallValue).method, 'of');
  });

  test('unbound fields become unknown values', () {
    final card = widget('StatCard').tree as ObjectValue;
    final inner = (card['child'] as ObjectValue)['child'] as ObjectValue;
    final value = ((inner['children'] as ListValue).items.first as ObjectValue)
        .arg(0);
    expect(value, isA<UnknownValue>());
    expect((value as UnknownValue).code, 'value');
  });

  test('follows project getters and static methods with bound arguments', () {
    // theme: AppTheme.light  →  static get light => _build(Brightness.light)
    final app = widget('MainApp').tree as ObjectValue;
    final theme = app['theme'] as RefValue;
    expect(theme.dotted, 'AppTheme.light');
    final call = theme.resolved as CallValue;
    expect(call.method, '_build');

    // _build returns ThemeData(colorScheme: colorScheme, ...) where
    // `final colorScheme = ColorScheme.fromSeed(brightness: brightness, ...)`.
    final data = call.result as ObjectValue;
    expect(data.type, 'ThemeData');
    final scheme = data['colorScheme'] as ObjectValue;
    expect(scheme.displayName, 'ColorScheme.fromSeed');
    expect((scheme['brightness'] as RefValue).dotted, 'Brightness.light');
    final seed = scheme['seedColor'] as RefValue;
    expect(seed.dotted, 'seed');
    expect((seed.resolved as ObjectValue).type, 'Color');
  });

  test('inlines instance helper methods with named arguments', () {
    final profile = widget('ProfileScreen').tree as ObjectValue;
    final column = (profile['body'] as ObjectValue)['child'] as ObjectValue;
    final actions = (column['children'] as ListValue).items.last as CallValue;
    expect(actions.method, '_actions');
    final row = actions.result as ObjectValue;
    expect(row.type, 'Row');
    expect(row.source, 'lib/profile_screen.dart:40');
    final save = (row['children'] as ListValue).items.last as ObjectValue;
    final label = save['child'] as ObjectValue;
    expect((label.arg(0) as LiteralValue).value, 'Save');
  });
}
