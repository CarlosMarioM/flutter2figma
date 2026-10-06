# flutter2figma

[![pub package](https://img.shields.io/pub/v/flutter2figma.svg)](https://pub.dev/packages/flutter2figma)
[![CI](https://github.com/CarlosMarioM/flutter2figma/actions/workflows/ci.yml/badge.svg)](https://github.com/CarlosMarioM/flutter2figma/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> **Beta.** flutter2figma works on real apps, but not every widget or app
> setup is covered yet. Expect gaps, and please
> [report them](https://github.com/CarlosMarioM/flutter2figma/issues) with the
> widget or screen that didn't come out right.

Convert a Flutter UI that already exists into an **editable** Figma design.
You get frames, text layers, vector icons, color variables with light/dark
modes, text styles, and components.

```
Flutter project ──► static analysis ─┐
                ──► runtime capture ─┴► intermediate representation ──► design.json ──► Figma plugin
```

There are two ways to read the app:

| | Static (default) | Runtime (`--runtime`) |
| --- | --- | --- |
| How | Reads your code; the app never runs | Renders each screen with Flutter (`flutter test`) and records what it draws |
| Layout | Figma **auto layout**, rebuilt from Flutter's sizing rules | Flutter's **exact** positions (absolute layout) |
| Widgets | Those it has rules for; others become placeholders | All of them, including custom painters and packages |
| Needs | Nothing to run | The app must start in a test: see [Runtime mode](#runtime-mode) |

Both resolve your theme into color variables and text styles. Screens that
can't run fall back to static export, so `--runtime` never exports less.

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

> **Installing the Figma plugin.** Until it is published on Figma Community:
> 1. Download `flutter2figma-figma-plugin-<version>.zip` from the
>    [latest release](https://github.com/CarlosMarioM/flutter2figma/releases/latest)
>    and unzip it.
> 2. In the Figma desktop app, choose **Plugins → Development → Import plugin
>    from manifest…** and pick its `manifest.json`. This is only needed once.
>
> The source is in [`figma-plugin/`](figma-plugin/).

## What you get in Figma

| From Flutter | In Figma |
| --- | --- |
| Screens (classes whose `build` leads to a `Scaffold`, through providers, bloc builders, auth gates, …) | Frames, one per screen, with auto layout |
| `Row`, `Column`, `Padding`, `SizedBox`, `Expanded`, `Stack`, `Wrap`, … | Auto layout: direction, gap, padding, alignment, wrapping, fixed / hug / fill |
| Material widgets: buttons, `ListTile` (and switch/checkbox/radio tiles), chips, `NavigationBar`, `BottomNavigationBar`, switches, text fields, … | Frames sized and colored with Material 3 defaults, measured against Flutter |
| `Icons.*`, `CupertinoIcons`, asset images and SVGs | Vector icons and image fills |
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

## Runtime mode

```sh
flutter2figma export --runtime
```

flutter2figma writes a test into `.dart_tool/flutter2figma/` (deleted
afterwards), starts the app through its own `main()`, and shows each screen
in turn. Your project's files are not changed.

**It runs your app's code.** Only use it on code you trust.

What it handles by itself:

- **Startup and providers.** The real `main()` runs, so dependency injection
  and app-level providers are set up. Providers that the app's first route
  puts around its screen are also given to every other screen, and screens
  wrapped by another widget class (`MenuScreen` providing blocs to `MenuPage`)
  are shown through that wrapper.
- **Constructor arguments.** Screens are built with placeholder values for
  simple required parameters (`String` gets its parameter name, numbers `0`,
  nullables `null`, ...).
- **Common plugins.** `shared_preferences` and `flutter_secure_storage` get
  in-memory fakes.
- **Fonts.** Real fonts are loaded so text measures as on a device. Families
  the app names but doesn't bundle fall back to Roboto, as on Android.

When a screen still can't start, add `test/flutter2figma_setup.dart` to the
app. Every function is optional:

```dart
import 'package:flutter/widgets.dart';

/// Runs before main(): mocks, fake repositories, dependency injection.
Future<void> setUp() async {}

/// Wraps every screen, e.g. with the providers a route gives it.
Widget wrapScreen(String name, Widget screen) => screen;

/// Builds screens that need real arguments; return null for the rest.
Widget? buildScreen(String name) => switch (name) {
  'ProductScreen' => ProductScreen(product: Product.sample()),
  _ => null,
};
```

The export lists every screen it couldn't render and why (`-v` shows the
rest). Add `--screenshots shots/` to also save Flutter's own render of each
screen, to compare with the Figma import.

### Preview

```sh
flutter2figma export --runtime --preview
```

also writes `preview.html` next to `design.json`: every screen drawn from
`design.json` in the browser, beside Flutter's own render, with a wipe slider
between the two and a toggle that outlines what each Figma layer will be
(vector, text or image). The app's fonts are embedded, so it opens offline.
It is a quick check of an export before importing it; the browser and Figma
can still differ in details. Without `--runtime`, it shows the export alone.

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
| `--runtime` | off | Render the screens with Flutter (see [Runtime mode](#runtime-mode)) |
| `--[no-]auto-layout` | on | With `--runtime`: rows and columns become auto layout where it keeps Flutter's positions |
| `--screenshots` | | With `--runtime`: save Flutter's render of each screen (PNG) in this directory |
| `--preview` | off | Also write `preview.html` (see [Preview](#preview)) |
| `--flutter` | detected | Flutter command for `--runtime`, e.g. `"fvm flutter"` |
| `-v, --verbose` | off | Also show info diagnostics |

## Dart API

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter2figma/flutter2figma.dart';

Future<void> main() async {
  // runtime: true renders the screens with Flutter (see Runtime mode).
  final result = await exportProject('path/to/app', runtime: true);
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
- **Images:** asset images (`Image.asset`, `AssetImage`, `DecorationImage`,
  `SvgPicture.asset`) are embedded in `design.json`; network, file and
  in-memory images are placeholders. Icons from Material icons (`Icons.*`)
  and `CupertinoIcons` are exact vectors read from the fonts the app ships;
  icons from other fonts are placeholders.
  `GridView` cell heights are estimated from the screen width.
- **Runtime mode** records each screen in the state it starts in, and keeps
  only the visible part of scrolling content. What custom painters draw
  becomes vectors (shapes, solid fills and strokes; gradients fill their
  shape as an image). Blurs, blend modes, shadows and text they draw are
  images: a painter's text can't be read back, so it isn't editable, and
  text a painter draws without naming a font family renders as boxes in
  tests. Painters that use layers with filters, vertices or atlases stay one
  image.
- **Not supported yet:**
  - tab bars, navigation rails and drawers, dialogs and sheets;
  - Cupertino widgets, Material 2 themes, and input/chip/list tile/navigation
    bar component themes.
- **Fonts** are exported by family name; the plugin substitutes any font
  that isn't installed in Figma.

## Documentation

| | |
| --- | --- |
| [doc/design-json.md](doc/design-json.md) | The `design.json` format, for building your own importer or tooling |
| [doc/architecture.md](doc/architecture.md) | How the pipeline works: analysis, theme, layout model, design system |
| [doc/development.md](doc/development.md) | Setup, tests, adding widget support, debugging |
| [figma-plugin/README.md](figma-plugin/README.md) | The Figma plugin: install, develop, release |
| [doc/releasing.md](doc/releasing.md) | How to cut a release: versions, tag, pub.dev, Figma plugin |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Checks before a pull request |
| [SECURITY.md](SECURITY.md) | Reporting vulnerabilities; what the tool can and can't do |

Bugs and wrong exports:
[open an issue](https://github.com/CarlosMarioM/flutter2figma/issues/new/choose)
with the diagnostics from `flutter2figma export -v`.

## License

MIT. See [LICENSE](LICENSE).
