# Flutter2Figma

Turn a Flutter UI that already exists into an **editable** Figma design: real
frames, auto layout, text layers and styles. It doesn't take screenshots.

```
Flutter project ──► Dart analyzer ──► Flutter UI IR ──► Figma renderer ──► design.json ──► Figma plugin
   (.dart)         (resolved AST)    (framework-free)   (Figma vocabulary)                  (editable frames)
```

## Status

The first vertical slice from the build plan (§17) works end to end:
`examples/basic` → `design.json` → Figma frames with auto layout, spacing,
typography, colors, radii and shadows. The output is checked against a golden
file that both the Dart CLI and the plugin tests use.

The app's own theme is read from `MaterialApp`:
- `theme`/`darkTheme` and `themeMode`;
- the color scheme, including `ColorScheme.fromSeed`;
- `fontFamily`, `textTheme` and GoogleFonts;
- the app bar, card and button themes;
- nested `Theme` widgets.

A Flutter test checks the result against the theme Flutter itself resolves.

The export also carries a **design system** that the plugin creates in Figma:

| Flutter | Figma |
| --- | --- |
| `ColorScheme` roles, for `theme` and `darkTheme` | Color variables with **Light/Dark modes**; switching the mode recolors the screens |
| `AppColors.brand`-style project constants that are painted | Color variables (`AppColors/brand`) |
| `textTheme` entries | Text styles (`TextTheme/bodyMedium`, …) |
| M3 elevation levels | Effect styles (`Elevation/level1`…`5`) |
| Material buttons | A `Button` component set with `Type` × `State` (× `Icon`) variants |
| Project widgets used 2+ times (`StatCard`) | Components, with instances in the screens |

Paints, text and shadows are bound to these only when they came from them.
For example, `Theme.of(context).colorScheme.primary` binds to
`ColorScheme/primary`, but a literal `Color(0xFF...)` with the same value does
not. Instances differ from their master only in text, which is applied as
overrides. Any other visual difference becomes a separate variant, so every
instance looks exactly like the widget it replaces.

Not built yet:
- `validate` (screenshot diff);
- `--runtime` mode;
- Figma → Flutter generation;
- spacing and radius tokens.

## Quick start

Requirements: Dart 3.11+, [FVM](https://fvm.app) (the Flutter version is pinned in `.fvmrc`), Node 18+.

```sh
# 1. Dependencies
dart pub get
(cd examples/basic && fvm flutter pub get)   # the analyzer needs the Flutter SDK resolved
(cd figma-plugin && npm install && npm run build)

# 2. Analyze / export
dart run flutter2figma analyze examples/basic
dart run flutter2figma export examples/basic -o build/flutter2figma
dart run flutter2figma export examples/basic --brightness dark -o build/dark
dart run flutter2figma export examples/basic --no-design-system   # plain frames only
#   → build/flutter2figma/design.json   (import this in Figma)
#   → build/flutter2figma/ir.json       (the intermediate representation)
```

```
$ dart run flutter2figma export examples/basic
Analyzing …/examples/basic...
Building intermediate representation...
Generating Figma document...

✓ Export complete

  2 screens
  32 nodes
```

To import into Figma (desktop app): **Plugins → Development → Import plugin from
manifest…** → `figma-plugin/manifest.json`. Run it, then drop `design.json` on the
plugin window. Each export creates a new page named after the project.

Any Flutter project works the same way: run `fvm flutter pub get` (or
`flutter pub get`) in it, then `dart run flutter2figma export path/to/app`.

## How it works

| Layer | Package | Input → output |
| --- | --- | --- |
| Analyzer | `packages/analyzer` | Resolves every library under `lib/` with `package:analyzer` and turns each widget class's `build` into a tree of `DartValue`s (constructor calls, literals, references, calls). It never runs Dart. `const` references are followed into their declarations, including Flutter's own source, so `Colors.blue` arrives as `MaterialColor(0xFF2196F3, …)`. Project widgets are inlined, with constructor arguments substituted for fields. The analyzer also follows the project's own getters, `final`s and functions/methods, so `AppTheme.light` and `_buildHeader()` resolve too. |
| Compiler | `packages/compiler` | Extracts the app's `ThemeData` the way Flutter resolves it. For `fromSeed` it uses the same `material_color_utilities` version as Flutter. It then interprets the widget tree against that theme, and a small layout model (tight/loose/bounded constraints) that decides fixed, hug or fill per axis. It folds wrappers such as `Padding` → frame padding and `SizedBox` spacers → auto-layout gap, but only when the result renders identically. |
| IR | `packages/ir` | Framework-independent frames and text with sizing, layout, paint and typography. It also records where each node came from: the Flutter widgets that produced it and their `file:line`. |
| Renderer | `packages/figma` | Maps IR to Figma Plugin API names and enums (`layoutMode`, `layoutSizingHorizontal`, `primaryAxisAlignItems`, …). Where Figma rejects a combination, it downgrades the node and emits a warning. |
| Plugin | `figma-plugin` | Loads fonts, falling back to the nearest weight and then to Inter. Builds nodes in the order Figma requires and places absolute and Stack children. Writes the origin and source of each node to plugin data. |
| CLI | `packages/cli` | `analyze`, `export`. |

More detail: [docs/architecture.md](docs/architecture.md).

### Widget coverage

- **Layout:** Scaffold (appBar, body, FAB), Container, Padding, Center, Align, SizedBox (+ expand/shrink/square), Row, Column, Flex, Stack/Positioned, Expanded, Flexible, Spacer, ListView (+ `.builder`, `.separated`), SingleChildScrollView.
- **Content:** Text, Text.rich/RichText (plain text), DefaultTextStyle, Icon and Image (both as placeholders).
- **Controls:** Elevated/Filled/FilledTonal/Outlined/Text buttons (+ `.icon`), IconButton, FloatingActionButton.
- **Surfaces:** Card (+ filled/outlined), Material, DecoratedBox, ColoredBox, ClipRRect, Divider.
- **Values:** EdgeInsets, BorderRadius, Border, BoxShadow, shapes, `Colors.*`, shades, `Color(...)`, `withOpacity`/`withValues`, `Theme.of(context).colorScheme.*` and `.textTheme.*`, `copyWith`/`merge`, `ButtonStyle`/`styleFrom`.
- **Pass-through** (child exported as-is): SafeArea, GestureDetector, InkWell, Semantics, Opacity, and about 30 others.

Anything else is exported as a magenta `⚠` placeholder, or passed through if it has a
`child`, and reported as a diagnostic. It never fails silently.

### Known limits (static mode)

- **Conditional UI:** `a ? b : c` and collection `if` export the `true` branch, with an info diagnostic. Plan: variants.
- **Lists:** `ListView.builder` renders 3 sample items when `itemCount` isn't a literal.
- **Missing values:** values that need runtime state become `{placeholders}` in text. Examples: fields without a call site, parameters of closures, and results of SDK or package methods.
- **Icons and images:** exported as placeholders. Gradients become their first color.
- **Theme:**
  - Other component themes are listed as "not applied" diagnostics. These include input decoration, chips and navigation bars.
  - Material 2 themes (`useMaterial3: false`) and `ColorScheme.fromSwatch` are exported with Material 3 defaults, with a warning.
  - Fonts are exported by family name. The Figma plugin substitutes any that aren't installed.
- **Design system:**
  - Spacing and radius aren't tokens yet.
  - Components are recognized for buttons and repeated project widgets only. Built-in widgets like `Card` or `ListTile` are not components.
  - The component master is the widget's first occurrence.
  - A Figma plan that allows only one variable mode gets just the Light mode, with a note in the plugin.
  - Re-importing updates variables and styles by name. Components are recreated on each import's page.

## Development

Full guide: [docs/development.md](docs/development.md). It covers setup, adding widget support, adding IR properties end to end, plugin development in Figma, debugging and known gotchas.

```sh
# Dart (from each package dir, or loop)
for p in ir analyzer compiler figma cli; do (cd packages/$p && dart test); done
dart analyze

# Plugin: typecheck, bundle, and run against a strict mock of the Figma API
cd figma-plugin && npx tsc --noEmit && npm run build && npm test

# Theme ground truth (Flutter resolves the example's theme)
cd examples/basic && fvm flutter test

# After an intentional output change, refresh the shared golden:
cd packages/cli && UPDATE_GOLDENS=1 dart test
```

The plugin tests use `test/figma-mock.ts`, which throws wherever the real API does.
For example: FILL outside auto layout, HUG on a non-auto-layout frame, or
editing text before its font loads. This lets the importer be tested without
Figma. It's still a mock, so try new node types in real Figma too.

## Repository layout

```
packages/
  ir/         IR model + JSON
  analyzer/   Dart AST → DartValue trees
  compiler/   DartValue → IR (Material 3 defaults, layout model, simplification)
  figma/      IR → design.json
  cli/        flutter2figma analyze | export   (+ golden: test/goldens/basic.design.json)
figma-plugin/ TypeScript plugin that imports design.json
examples/basic/  Flutter app: the §17 screen + a profile screen
docs/
```
