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

Not built yet: `validate` (screenshot diff), `--runtime` mode, design-system
extraction, Figma → Flutter generation.

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
| Analyzer | `packages/analyzer` | Resolves every library under `lib/` with `package:analyzer` and turns each widget class's `build` into a tree of `DartValue`s (constructor calls, literals, references, calls). It never runs Dart. `const` references are followed into their declarations, including Flutter's own source, so `Colors.blue` arrives as `MaterialColor(0xFF2196F3, …)`. Project widgets are inlined, with constructor arguments substituted for fields. |
| Compiler | `packages/compiler` | Interprets the widget tree with Material 3 defaults transcribed from the pinned Flutter SDK, and a small layout model (tight/loose/bounded constraints) that decides fixed, hug or fill per axis. It folds wrappers such as `Padding` → frame padding and `SizedBox` spacers → auto-layout gap, but only when the result renders identically. |
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
- **Missing values:** values that need runtime state (fields without a call site, method results) become `{placeholders}` in text.
- **Icons and images:** exported as placeholders. Gradients become their first color.
- **Theme:** the default `ThemeData()` Material 3 baseline is assumed. Custom `ThemeData` and `ColorScheme.fromSeed` aren't read yet.

## Development

Full guide: [docs/development.md](docs/development.md). It covers setup, adding widget support, adding IR properties end to end, plugin development in Figma, debugging and known gotchas.

```sh
# Dart (from each package dir, or loop)
for p in ir analyzer compiler figma cli; do (cd packages/$p && dart test); done
dart analyze

# Plugin: typecheck, bundle, and run against a strict mock of the Figma API
cd figma-plugin && npx tsc --noEmit && npm run build && npm test

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
