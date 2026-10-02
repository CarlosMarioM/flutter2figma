import 'package:flutter2figma/analyzer.dart';
import 'package:flutter2figma/compiler.dart';
import 'package:flutter2figma/ir.dart';
import 'package:test/test.dart';

import 'builders.dart';

final fonts = projectIconFonts('example');

IrFrame compile(DartValue body, {Map<String, DartValue> scaffold = const {}}) =>
    FlutterCompiler(iconFonts: fonts)
        .compileScreen(
          'Test',
          w('Scaffold', named: {'body': body, ...scaffold}),
          null,
        )
        .root;

IrNode bodyOf(DartValue body) => compile(body).children.single;

ObjectValue icon(String name) => w('Icon', positional: [ref('Icons.$name')]);
const onTap = FunctionValue();

void main() {
  group('ListTile', () {
    test('one line: M3 padding, gap, leading slot and height', () {
      final tile =
          bodyOf(
                w(
                  'ListTile',
                  named: {
                    'leading': icon('person'),
                    'title': text('Ada'),
                    'trailing': icon('chevron_right'),
                  },
                ),
              )
              as IrFrame;
      expect(tile.role, 'list-tile');
      expect(tile.direction, IrLayoutDirection.horizontal);
      expect(tile.width, const IrSizing.fill());
      expect(tile.minHeight, 56);
      expect(
        [tile.padding.left, tile.padding.right, tile.padding.top],
        [16, 24, 8],
      );
      expect(tile.gap, 16);
      expect(tile.crossAlign, IrCrossAlign.center);
      final [leading, texts, trailing] = tile.children;
      expect((leading as IrFrame).minWidth, 24);
      expect((leading.children.single as IrFrame).name, 'Icon/person');
      expect((texts as IrFrame).width, const IrSizing.fill());
      final title = texts.children.single as IrText;
      expect(title.style.token, 'TextTheme/bodyLarge');
      expect(title.style.color.token, 'ColorScheme/onSurface');
      expect((trailing as IrFrame).name, 'Icon/chevron_right');
    });

    test('two and three lines, dense, selected and disabled', () {
      IrFrame tile(Map<String, DartValue> named) =>
          bodyOf(w('ListTile', named: {'title': text('T'), ...named}))
              as IrFrame;
      final two = tile({'subtitle': text('S')});
      expect(two.minHeight, 72);
      final subtitle = (two.children.single as IrFrame).children.last as IrText;
      expect(subtitle.style.token, 'TextTheme/bodyMedium');
      expect(subtitle.style.color.token, 'ColorScheme/onSurfaceVariant');

      final three = tile({'subtitle': text('S'), 'isThreeLine': lit(true)});
      expect(three.minHeight, 88);
      expect(three.crossAlign, IrCrossAlign.start);
      expect(tile({'dense': lit(true)}).minHeight, 48);

      Iterable<IrText> titles(IrFrame t) =>
          (t.children.single as IrFrame).children.cast<IrText>();
      expect(
        titles(tile({'selected': lit(true)})).single.style.color.token,
        'ColorScheme/primary',
      );
      final disabled = titles(tile({'enabled': lit(false)})).single.style.color;
      expect(
        [disabled.token, disabled.a],
        ['ColorScheme/onSurface', closeTo(0.38, 0.01)],
      );
    });

    test('SwitchListTile puts a shrink-wrapped switch at the end', () {
      final tile =
          bodyOf(
                w(
                  'SwitchListTile',
                  named: {
                    'title': text('Wi-Fi'),
                    'value': lit(true),
                    'onChanged': onTap,
                  },
                ),
              )
              as IrFrame;
      expect(tile.name, 'SwitchListTile');
      final control = tile.children.last as IrFrame;
      expect(
        [control.width, control.height],
        [const IrSizing.fixed(60), const IrSizing.fixed(40)],
      );
    });

    test('RadioListTile leads with its radio', () {
      final tile =
          bodyOf(
                w(
                  'RadioListTile',
                  named: {
                    'title': text('A'),
                    'value': lit(1),
                    'groupValue': lit(1),
                    'onChanged': onTap,
                  },
                ),
              )
              as IrFrame;
      final leading =
          (tile.children.first as IrFrame).children.single as IrFrame;
      expect(leading.role, 'radio');
      expect(leading.width, const IrSizing.fixed(40));
    });
  });

  group('chips', () {
    IrFrame chip(String type, Map<String, DartValue> named, {String? ctor}) =>
        unwrap(
          bodyOf(w(type, ctor: ctor, named: {'label': text('Tag'), ...named})),
        );

    test('Chip: outlined, 32 px, 17 px to the label', () {
      final c = chip('Chip', {});
      expect(c.role, 'chip');
      expect(c.height, const IrSizing.fixed(32));
      expect([c.padding.left, c.padding.right], [17, 17]);
      expect(c.corners, const IrCorners.all(8));
      expect(c.stroke!.color.token, 'ColorScheme/outlineVariant');
      expect(c.fill, isNull);
      final label = c.children.single as IrText;
      expect(label.style.token, 'TextTheme/labelLarge');
      expect(label.style.color.token, 'ColorScheme/onSurfaceVariant');
    });

    test('avatar and delete icon take 18 px, 10 px from the edge', () {
      final c = chip('Chip', {'avatar': icon('person'), 'onDeleted': onTap});
      expect([c.padding.left, c.padding.right, c.gap], [10, 10, 9]);
      final avatar = c.children.first as IrFrame;
      final delete = c.children.last as IrFrame;
      expect(
        [avatar.width, avatar.height],
        [const IrSizing.fixed(18), const IrSizing.fixed(18)],
      );
      expect(delete.name, 'Icon/cancel');
    });

    test('selected FilterChip: tonal fill and a checkmark', () {
      final c = chip('FilterChip', {
        'selected': lit(true),
        'onSelected': onTap,
      });
      expect(c.fill!.token, 'ColorScheme/secondaryContainer');
      expect(c.stroke, isNull);
      expect((c.children.first as IrFrame).name, 'Icon/check');
      expect(
        (c.children.last as IrText).style.color.token,
        'ColorScheme/onSecondaryContainer',
      );
    });

    test('elevated ActionChip and disabled chips', () {
      final elevated = chip('ActionChip', {
        'onPressed': onTap,
      }, ctor: 'elevated');
      expect(elevated.fill!.token, 'ColorScheme/surfaceContainerLow');
      expect(elevated.shadows, isNotEmpty);
      final disabled = chip('ActionChip', {});
      expect(
        (disabled.children.single as IrText).style.color.a,
        closeTo(0.38, 0.01),
      );
    });

    test('InputChip deletes with Icons.clear; padded for touch', () {
      final target =
          bodyOf(
                w(
                  'InputChip',
                  named: {'label': text('Ada'), 'onDeleted': onTap},
                ),
              )
              as IrFrame;
      expect(target.role, 'tap-target');
      expect(target.minHeight, 48);
      final c = unwrap(target);
      expect((c.children.last as IrFrame).name, 'Icon/clear');
    });
  });

  group('navigation bars', () {
    ObjectValue destination(String label, String iconName) => w(
      'NavigationDestination',
      named: {'icon': icon(iconName), 'label': lit(label)},
    );

    test('NavigationBar: 80 px, indicator on the selected destination', () {
      final screen = compile(
        text('body'),
        scaffold: {
          'bottomNavigationBar': w(
            'NavigationBar',
            named: {
              'selectedIndex': lit(1),
              'destinations': list([
                destination('Home', 'home'),
                destination('People', 'people'),
              ]),
            },
          ),
        },
      );
      // The body fills the space above the bar.
      expect(screen.children.map((c) => c.name), ['Body', 'NavigationBar']);
      expect(screen.children.first.height, const IrSizing.fill());

      final bar = screen.children.last as IrFrame;
      expect(bar.height, const IrSizing.fixed(80));
      expect(bar.width, const IrSizing.fill());
      expect(bar.fill!.token, 'ColorScheme/surfaceContainer');
      final [home, people] = bar.children.cast<IrFrame>();
      expect(
        [home.name, home.width, home.gap],
        ['Home', const IrSizing.fill(), 4],
      );
      final homeIndicator = home.children.first as IrFrame;
      final peopleIndicator = people.children.first as IrFrame;
      expect(
        [homeIndicator.width, homeIndicator.height],
        [const IrSizing.fixed(64), const IrSizing.fixed(32)],
      );
      expect(homeIndicator.fill, isNull);
      expect(peopleIndicator.fill!.token, 'ColorScheme/secondaryContainer');
      final label = people.children.last as IrText;
      expect(label.style.token, 'TextTheme/labelMedium');
      expect(label.style.color.token, 'ColorScheme/onSurface');
    });

    test(
      'BottomNavigationBar: primary selection, 14/12 px labels, FAB above',
      () {
        final screen = compile(
          text('body'),
          scaffold: {
            'floatingActionButton': w(
              'FloatingActionButton',
              named: {'onPressed': onTap, 'child': icon('add')},
            ),
            'bottomNavigationBar': w(
              'BottomNavigationBar',
              named: {
                'items': list([
                  w(
                    'BottomNavigationBarItem',
                    named: {'icon': icon('home'), 'label': lit('Home')},
                  ),
                  w(
                    'BottomNavigationBarItem',
                    named: {'icon': icon('search'), 'label': lit('Find')},
                  ),
                ]),
              },
            ),
          },
        );
        final bar =
            screen.children.firstWhere((c) => c.name == 'BottomNavigationBar')
                as IrFrame;
        expect(bar.minHeight, 56);
        expect(bar.shadows, isNotEmpty);
        final [home, find] = bar.children.cast<IrFrame>();
        final homeLabel = home.children.last as IrText;
        final findLabel = find.children.last as IrText;
        expect(homeLabel.style.color.token, 'ColorScheme/primary');
        expect([homeLabel.style.fontSize, findLabel.style.fontSize], [14, 12]);
        expect(findLabel.style.color.a, closeTo(0.54, 0.01));
        final fab = screen.children.firstWhere(
          (c) => c.name == 'FloatingActionButton',
        );
        expect(fab.position!.bottom, 16 + 56);
      },
    );
  });

  test('CircleAvatar: a clipped circle in primaryContainer', () {
    final avatar =
        bodyOf(
              w(
                'CircleAvatar',
                named: {'radius': lit(24), 'child': text('AL')},
              ),
            )
            as IrFrame;
    expect(
      [avatar.width, avatar.height],
      [const IrSizing.fixed(48), const IrSizing.fixed(48)],
    );
    expect(avatar.corners.topLeft, 24);
    expect(avatar.clip, isTrue);
    expect(avatar.fill!.token, 'ColorScheme/primaryContainer');
    final label = avatar.children.single as IrText;
    expect(label.style.token, 'TextTheme/titleMedium');
    expect(label.style.color.token, 'ColorScheme/onPrimaryContainer');
  });

  test('Wrap wraps in the available width', () {
    final wrap =
        bodyOf(
              w(
                'Wrap',
                named: {
                  'spacing': lit(8),
                  'runSpacing': lit(4),
                  'children': list([text('a'), text('b')]),
                },
              ),
            )
            as IrFrame;
    expect(wrap.direction, IrLayoutDirection.horizontal);
    expect(wrap.wrap, isTrue);
    expect(wrap.width, const IrSizing.fill());
    expect([wrap.gap, wrap.runGap], [8, 4]);
  });
}
