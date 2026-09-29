# flutter2figma

Convert a Flutter UI that already exists into an **editable** Figma design.
You get real frames with auto layout, text layers, color variables with
light/dark modes, text styles, and components. It doesn't take screenshots.

```
Flutter project ──► static analysis ──► intermediate representation ──► design.json ──► Figma plugin
```

flutter2figma reads your code and never runs the app. It resolves your theme
the way Flutter does, including `ColorScheme.fromSeed`, custom fonts and
component themes, and maps widgets to Figma auto layout following Flutter's
own sizing rules.

## Install

```sh
dart pub global activate flutter2figma
```

Requires Dart 3.11 or later. The Flutter project you export must be resolved
(`flutter pub get`).

## Export

```sh
cd path/to/your_app
flutter pub get
flutter2figma export
```

```
✓ Export complete

  6 screens
  165 nodes
  51 color variables (Light / Dark)
  15 text styles
  5 effect styles
  5 components (12 variants)

  build/flutter2figma/design.json   ← import with the Figma plugin
  build/flutter2figma/ir.json
```

Then, in the Figma desktop app, open the **Flutter2Figma** plugin and drop
`design.json` on it. Each export creates a new page. The design system is
reused across imports: variables and styles are updated in place.

> The Figma plugin lives in this repository under
> [`figma-plugin/`](figma-plugin/). Until it is published on Figma Community,
> load it with **Plugins → Development → Import plugin from manifest…** after
> running `npm install && npm run build` in that folder.

## What you get in Figma

| From Flutter | In Figma |
| --- | --- |
| Screens (classes whose `build` leads to a `Scaffold`, through providers, bloc builders, auth gates, …) | Frames, one per screen, with auto layout |
| `Row`, `Column`, `Padding`, `SizedBox`, `Expanded`, `Stack`, … | Auto layout: direction, gap, padding, alignment, fixed / hug / fill |
| `ColorScheme` roles for `theme` and `darkTheme` | Color variables with **Light/Dark modes**; switching the mode recolors the screens |
| Painted project constants such as `AppColors.brand` | Color variables |
| `textTheme` entries | Text styles (`TextTheme/bodyMedium`, …) |
| Material elevation | Effect styles (`Elevation/level1`–`5`) |
| Material buttons | A `Button` component set with variants for type and state |
| Your widgets used two or more times | Components, with instances in the screens |

Every layer records the Flutter widgets it came from and their `file:line`.

Values bind to tokens only when they came from them. `colorScheme.primary`
becomes the `ColorScheme/primary` variable, but a hard-coded `Color` with the
same value stays a hard-coded color.

## Commands

| Command | Does |
| --- | --- |
| `flutter2figma export [project]` | Writes `design.json` and `ir.json` |
| `flutter2figma analyze [project]` | Lists screens, widgets and analysis problems (`--json` for the widget trees) |
| `flutter2figma theme [project]` | Prints the resolved Material theme as JSON |
| `flutter2figma --version` | Prints the version |

`export` options:

| Option | Default | |
| --- | --- | --- |
| `-o, --output` | `build/flutter2figma` | Output directory |
| `--brightness` | `auto` | `light`, `dark`, or `auto` (follows `themeMode`) |
| `--screen-size` | `390x844` | Frame size for screens |
| `--[no-]design-system` | on | Variables, styles and components |
| `--min-component-uses` | `2` | Uses before one of your widgets becomes a component |
| `-v, --verbose` | off | Also show info diagnostics |

## Dart API

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter2figma/flutter2figma.dart';

Future<void> main() async {
  final result = await exportProject('path/to/app');
  File('design.json').writeAsStringSync(jsonEncode(result.design));
  for (final d in result.diagnostics) {
    print(d);
  }
}
```

The stages are also available on their own:
- `package:flutter2figma/analyzer.dart`: Flutter source → widget trees;
- `compiler.dart`: widget trees → IR, including theme and design system;
- `ir.dart`: the intermediate representation;
- `figma.dart`: IR → `design.json`.

## Limitations

flutter2figma exports what can be known **without running the app**. It
never skips anything silently. Every approximation is reported as a
diagnostic, and anything it can't draw becomes a magenta `⚠` placeholder.

- **State-dependent UI** exports one state, usually the screen's **initial**
  state:
  - Values that are statically known are used: constants, field
    initializers, constructor defaults (including freezed `@Default`), and a
    bloc/cubit's initial `super(...)` state, as seen by `BlocBuilder`,
    `BlocConsumer` and `context.read/watch`. So
    `if (state.error != null) …` or `Text('${state.score}')` render as they
    would on the first frame.
  - Otherwise, for `a ? b : c`, `switch` expressions and early returns, the
    branch with more content is used.
  - Lists built from runtime data show 3 sample items; loops over literal
    lists show the real items.
- **Icons and images** are placeholders, and gradients use their first color.
  `GridView` cell heights are estimated from the screen width.
- **Not supported yet:**
  - `ListTile`, chips, navigation and tab bars, dialogs and sheets;
  - Cupertino widgets, Material 2 themes, and input/chip/list tile component
    themes.
- **Fonts** are exported by family name; the plugin substitutes any font
  that isn't installed in Figma.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). [doc/architecture.md](doc/architecture.md)
explains how the pipeline works, and [doc/development.md](doc/development.md)
covers setup, tests and how to add widget support.

## License

MIT. See [LICENSE](LICENSE).
