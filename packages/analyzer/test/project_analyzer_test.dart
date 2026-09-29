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
    // SettingsRoute only wraps SettingsScreen, so it isn't listed.
    expect(
      analysis.screens.map((s) => s.name),
      unorderedEquals(['HomeScreen', 'ProfileScreen', 'SettingsScreen']),
    );
    expect(widget('SettingsRoute').scaffoldPath, ['SettingsScreen']);
    expect(widget('HomeScreen').source, 'lib/home_screen.dart:4');
  });

  group('real-world patterns (SettingsScreen)', () {
    late ConditionalValue gate;
    late List<DartValue> items;

    setUp(() {
      // if (_loading) { return Scaffold(spinner); } return Scaffold(content);
      gate = widget('SettingsScreen').tree as ConditionalValue;
      final content = gate.otherwise as ObjectValue;
      items = ((content['body'] as ObjectValue)['children'] as ListValue).items;
    });

    test('early returns become a conditional chain', () {
      expect(gate.condition, '_loading');
      expect((gate.then as ObjectValue).type, 'Scaffold');
      expect((gate.otherwise as ObjectValue).type, 'Scaffold');
    });

    String? label(DartValue v) {
      final o = v is ObjectValue && v.type == 'Padding'
          ? v['child'] as ObjectValue
          : v as ObjectValue;
      return (o.arg(0) as LiteralValue).asString;
    }

    test('loops over literal lists are unrolled with the item bound', () {
      // for (final toggle in _toggles) ...  (a const field)
      expect(items.skip(2).take(3).map(label), [
        'Notifications',
        'Dark mode',
        'Autoplay',
      ]);
      // ...['Privacy', 'About'].map((label) => Text(label))
      final mapped = items[5] as CallValue;
      expect((mapped.result as ListValue).items.map(label), [
        'Privacy',
        'About',
      ]);
    });

    test('switch expressions become conditionals, first case first', () {
      final builder = items[6] as ObjectValue;
      expect(builder.type, 'ValueListenableBuilder');
      final result = (builder['builder'] as FunctionValue).returns;
      expect(result, isA<ConditionalValue>());
      final chain = result as ConditionalValue;
      expect((chain.then as ObjectValue).type, 'LinearProgressIndicator');
      expect(chain.otherwise, isA<ConditionalValue>());
    });

    test('marks which widget classes are declared in the project', () {
      final button = items.last as ObjectValue;
      expect(button.type, 'FilledButton');
      expect(button.inProject, isFalse);

      final profile = widget('ProfileScreen').tree as ObjectValue;
      final column = (profile['body'] as ObjectValue)['child'] as ObjectValue;
      final row = (column['children'] as ListValue).items[2] as ObjectValue;
      final expanded =
          (row['children'] as ListValue).items.first as ObjectValue;
      final statCard = expanded['child'] as ObjectValue;
      expect(statCard.type, 'StatCard');
      expect(statCard.inProject, isTrue);
    });
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
    expect(seed.dotted, 'AppTheme.seed');
    expect(seed.inProject, isTrue);
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
