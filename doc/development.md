# Development guide

This guide is for people working on Flutter2Figma. Start with
[architecture.md](architecture.md) for the layer design. This page covers how
to get set up, how to change things, and how to check your changes.

## Setup

| Tool | Version | Used for |
| --- | --- | --- |
| Dart SDK | 3.11+ | the package and CLI |
| [FVM](https://fvm.app) | 4.x | Flutter SDK for example apps (`.fvmrc` → `stable`) |
| Node | 18+ | Figma plugin build and tests |
| Figma desktop | any | manual plugin testing (plugins can't be side-loaded in the browser) |

```sh
dart pub get                            # the flutter2figma package
(cd example && fvm flutter pub get)     # required: the analyzer tests resolve it
(cd figma-plugin && npm install)
```

Always use `fvm flutter …`. There is no global `flutter`.
`example/` is a separate Flutter app with its own lockfile. It resolves
against the FVM-managed SDK, and it has no platform folders: run
`flutter create .` there if you want to run it.

## Repository map

```
pubspec.yaml, CHANGELOG.md, LICENSE, README.md   the pub package
bin/flutter2figma.dart         CLI entry point (`dart pub global activate`)
lib/
  flutter2figma.dart           exportProject() convenience API
  analyzer.dart / compiler.dart / ir.dart / figma.dart   public libraries per stage
  src/version.dart             packageVersion (kept equal to pubspec by test/version_test.dart)
  src/ir/model.dart            IR node model + JSON (the central contract)
  src/analyzer/values.dart     DartValue types (analyzer output)
  src/analyzer/project_analyzer.dart
                               project resolution, class/screen discovery, expression → DartValue
  src/compiler/compiler.dart   widget dispatch + per-widget handlers + sizing model
  src/compiler/evaluator.dart  DartValue → colors, insets, radii, text styles, alignment
  src/compiler/material_theme.dart   MaterialTheme (resolved theme), M3 baseline schemes / typescale / shadows
  src/compiler/theme_extractor.dart  MaterialApp → ThemeData → MaterialTheme
  src/compiler/color_scheme.dart     ColorScheme fallbacks, .light/.dark defaults, fromSeed
  src/compiler/component_extractor.dart  components and variants
  src/compiler/text_style.dart TextStyleSpec (partial style, merge, resolve)
  src/compiler/simplify.dart   wrapper folding pass
  src/figma/renderer.dart      IR → design.json
  src/cli/commands.dart        analyze / export / theme commands
test/                          one folder per stage; goldens/ holds the shared fixtures
example/                       reference Flutter app (also the pub.dev example)
figma-plugin/                  TypeScript Figma plugin (not part of the pub package)
  src/design.ts                design.json types + parseDesign
  src/importer.ts              builds Figma nodes (pure; takes a PluginAPI)
  src/design-system.ts         variables and styles upsert, paint binding
  src/code.ts                  plugin entry: UI messages → importer
  ui.html                      drop zone UI
  test/figma-mock.ts           strict fake Figma API
  test/importer.test.ts        node:test suite
  scripts/package.sh           builds the release zip
  listing/                     Figma Community listing text, icon, cover
tool/validate_app.sh           check any real app (theme, export, Figma import)
doc/                           this guide, architecture.md, design-json.md (format spec)
.github/workflows/             ci.yml, publish.yml (pub.dev), release-plugin.yml (zip)
SECURITY.md, CONTRIBUTING.md
```

## Everyday commands

```sh
# Run the tool
dart run flutter2figma analyze example
dart run flutter2figma analyze example --json      # dump DartValue trees
dart run flutter2figma export  example -o build/flutter2figma -v

# Dart checks
dart analyze
dart format lib bin test
dart test                     # everything; or e.g. `dart test test/compiler`

# Plugin checks
cd figma-plugin
npx tsc --noEmit
npm run build           # → dist/code.js
npm run watch           # rebuild on save while testing in Figma
npm test
```

`dart format` can split one-line `if` statements, which then triggers
`curly_braces_in_flow_control_structures`. Fix with
`dart fix --apply --code=curly_braces_in_flow_control_structures lib test`.

## Tests

| Suite | Where | Needs | What it covers |
| --- | --- | --- | --- |
| IR | `test/ir` | – | JSON round trip, colors |
| Analyzer | `test/analyzer` | `example` pub get | discovery, constants into the SDK, inlining, locals, bindings |
| Theme extraction | `test/compiler/theme_extraction_test.dart` | `example` pub get | static theme equals Flutter's resolved theme (fixture below) |
| Flutter ground truth | `example/test` | FVM Flutter | dumps the real `Theme.of(context)` into the fixture |
| Compiler | `test/compiler` | – | handlers, sizing, folding, theme behavior (`theme_test.dart`). Inputs are hand-built `DartValue`s (`w()`, `v()`, `lit()`, `ref()` helpers), so no SDK is needed |
| Renderer | `test/figma` | – | Figma enums, font style names, downgrades |
| Golden | `test/cli` | `example` pub get | full pipeline → `basic.design.json` |
| Runtime | `test/runtime` | `example` pub get, Flutter | converter on hand-written captures; harness generation; an end-to-end `--runtime` export of the example (runs `flutter test`, ~15 s) |
| Plugin | `figma-plugin/test` | the golden | imports the golden into the strict mock; fonts, stack/absolute placement |

The analyzer and golden tests resolve a real Flutter project. The first run
takes about 7 seconds. `test/compiler/real_world_test.dart` holds regressions
found by running against real apps; add to it when validation finds a new
pattern.

### CI

`.github/workflows/ci.yml` runs on every push to `main` and on pull
requests:
- **Dart job:** format, `dart analyze --fatal-infos`, `dart test`, the
  example's Flutter ground-truth test, and `dart pub publish --dry-run`;
- **Plugin job:** typecheck, tests and build.

Flutter is pinned to **3.41.9** in CI, the version the theme fixtures were
generated with. When you upgrade Flutter:
1. regenerate the fixtures (see *The theme fixture* below);
2. bump that pin in the same commit.

`publish.yml` reuses CI before publishing, so a red CI blocks a release.

### Validating against real apps

The example app covers what we built on purpose; real apps find what we
didn't. Run the validator on any resolved Flutter app (`flutter pub get`
done). It never writes to the app. Unlike `flutter2figma` itself, which only
reads source, the validator **runs the app's code** in a Flutter test (a
temporary copy) to get the ground-truth theme. Use it only on apps you
trust.

```sh
tool/validate_app.sh ~/Code/some_app lib/app.dart [out-dir]
#                    app root        file containing its MaterialApp
```

It reports three things:
1. **Theme.** It copies the app to a temp dir and runs a generated Flutter test
   (`tool/validate/`) that dumps `Theme.of(context)` below the app's
   `MaterialApp`, then diffs the result with `flutter2figma theme`. Expect
   `0 differences`. The test tries two modes:
   - `root`: pumps the app's real root (the argument of `runApp(...)`), so
     themes built from runtime state, such as a cubit's initial state,
     resolve exactly as in the app;
   - `expression`: if the root can't boot in a test (async setup, dependency
     injection, plugins), it falls back to
     `MaterialApp(theme: <the app's theme expression>)`.

   Flutter is imported with a prefix, so app classes named like Flutter's
   (e.g. `RootWidget`) don't clash. The Flutter command is the app's
   `.fvmrc`, else `flutter`, else `fvm spawn stable`.
2. **Export.** Screens, nodes and `⚠` placeholders per screen, and the
   warnings.
3. **Figma.** Imports the `design.json` through the strict plugin mock
   (`F2F_DESIGNS=<paths> npm test` does the same for any exports).

How to read the results:
- **Placeholders** should only remain for content that can't be drawn
  statically (`CustomPaint`, platform views).
- **Missing screens** usually mean an unfamiliar wrapper. Look at the
  class's tree with `flutter2figma analyze --json`.
- **A theme difference** means Flutter resolves something we don't model. Fix
  the extractor, then add the case to `theme_test.dart`.

### The golden

`test/goldens/basic.design.json` is the contract between the Dart
side and the plugin. When you change output on purpose:

```sh
UPDATE_GOLDENS=1 dart test test/cli
git diff test/goldens/            # review every change; this is what designers get
(cd figma-plugin && npm test)     # the plugin must still import it
```

Commit the golden together with the code that changed it.

### The theme fixture

`test/goldens/basic_theme.json` is written by **Flutter**,
not by us, and it is the reference the extractor must match. Regenerate it
when the example's theme or the Flutter version changes:

```sh
(cd example && UPDATE_GOLDENS=1 fvm flutter test test/theme_ground_truth_test.dart)
dart test test/compiler/theme_extraction_test.dart
```

If the second command fails after a Flutter upgrade, Flutter's theme
resolution changed. Fix the extractor rather than the fixture. To support a
new theme property, add it to both dumps, the Flutter test and
`describeTheme()` (in `material_theme.dart`), so it's checked against the real
thing.

### The layout fixture

`test/goldens/basic_layout.json` is also written by Flutter: the sizes it lays
out for a few example widgets on a 390×844 screen. The plugin test imports the
golden into the mock and expects the same sizes. Regenerate it like the theme
fixture:

```sh
(cd example && UPDATE_GOLDENS=1 fvm flutter test test/layout_ground_truth_test.dart)
(cd figma-plugin && npm test)
```

The mock has no font metrics (text is approximated), so widths that depend on
a label are compared loosely; heights must match.

### The Figma mock

`figma-mock.ts` implements only the API the importer uses. It **throws** where
Figma does, or where Figma would silently do something we consider a bug:

- `layoutSizing* = 'HUG'` on a frame that isn't auto layout (and isn't text)
- `layoutSizing* = 'FILL'` without an auto-layout parent, on an absolute
  child, or inside a parent that hugs that axis
- `layoutPositioning = 'ABSOLUTE'` without an auto-layout parent
- `minWidth`/`minHeight` on a frame that isn't auto layout
- setting `fontName` or `characters` before `loadFontAsync`
- `resize` below 0.01
- paints with unknown keys (e.g. a leftover `variable`), or RGBA in a solid
  paint's `color`
- `createVariable` / `setExplicitVariableModeForCollection` with a string id
  (`dynamic-page` requires the collection object)
- variable values for unknown modes; `addMode` beyond `maxModes`
  (`createMockFigma({ maxModes: 1 })` simulates a Figma plan limit)
- `createComponentFromNode` on a detached or non-frame node;
  `combineAsVariants` with non-components or names not shaped like
  `Prop=Value, …`

The mock also implements reparenting, `insertChild`, instance cloning, and
text/effect style application. Tests can inspect `variableList`,
`textStyleList()`, `effectStyleList()`, `collections` and each node's
`explicitModes`.

When the importer starts using a new API surface, add it to the mock with the
same strictness. Then check it once in real Figma, because the mock only
encodes rules we already know about.

## Adding support for a widget

Example: `Chip(label: Text('New'))`.

1. **Check what the analyzer produces.** Add the widget to `example` (or
   a scratch app) and run `analyze --json`. You'll see the `ObjectValue`, its
   named args, and whether constants resolved.

2. **Look up Flutter's defaults** in the pinned SDK. Don't write them from
   memory:
   ```sh
   F=~/fvm/versions/stable/packages/flutter/lib/src/material
   grep -n "class _ChipDefaultsM3" -A60 $F/chip.dart
   ```
   Add any new theme values to `material_theme.dart`.

3. **Write a handler** in `compiler.dart`:
   - Add a `case 'Chip':` in `_flutterWidget`, keyed on `displayName`
     (`Type` or `Type.ctor`).
   - Return an `IrFrame`/`IrText` with `origin: [w.type]` and a `role` if it's a
     semantic control.
   - Size it with the context box:
     - `_hugOrFill(c.box.forceW)` for content-sized widgets;
     - `_axis(...)` when the widget has explicit dimensions;
     - `_inner(...)` to derive the constraints for its children.
   - Compile children with `_widget(child, ctx)`. To change inherited text or
     icon color, use `c.withText(style, iconColor: …)`, as buttons do.
   - Read values through `eval` (`eval.color`, `eval.insets`, `eval.shape`,
     `eval.textStyle`, …). Add a new evaluator only for a new *value type*.
   - Report approximations with
     `_warn(message, w, severity: IrSeverity.info)`, or use `warning` when the
     output is noticeably wrong.

4. **Pure wrappers** that just render their child go in `_passThrough`.

5. **Test**: add a case to `compiler_test.dart` using the builders. If the
   example app uses the widget, refresh the golden.

6. Update the widget coverage list in `README.md`.

### Sizing checklist

For every axis, work out what Flutter would do, then express it as
fixed / hug / fill:

- Does the widget have an explicit size? → `fixed`. `double.infinity` in
  bounded space → `fill`.
- Does the parent force the size (tight constraints: `forceW`/`forceH`)? → `fill`.
- Does it expand to the maximum in bounded space (Center, a Container with no
  child, a Column's main axis with `max`)? → `fill` if bounded, else `hug`.
- Otherwise → `hug`.

Never make a child fill an axis on which its parent hugs. The renderer
downgrades that case with a warning, which means the compiler got something
wrong. `_adoptChildFill` already grows hugging wrappers whose child fills.

## Adding an IR property end to end

Example: layer opacity from `Opacity(opacity: 0.5)`.

1. `ir/model.dart`: add the field to `IrNode` (constructor, `toJson`,
   `fromJson`), and extend `model_test.dart`'s round trip.
2. `compiler.dart`: set it in the handler (here: take `Opacity` out of
   `_passThrough` and give it a handler).
3. `simplify.dart`: decide whether a wrapper carrying the property can still
   be folded. Usually it can't; see `IrFrame.isBare`.
4. `figma/renderer.dart`: emit the Figma property (`opacity`).
5. `figma-plugin/src/design.ts`: add it to the spec types.
6. `figma-plugin/src/importer.ts`: apply it. Mind the ordering rules below.
7. `figma-mock.ts`: add the property to the mock.
8. Tests on each layer, then refresh the golden.

If the change breaks old files, bump `irVersion` or `designVersion`. The
plugin rejects files newer than it knows (`parseDesign`).

## Stress test

`tool/stress.sh` exports `showcase/` (a dense multi-screen app) statically
and with `--runtime`, saves Flutter's render of every screen to
`build/showcase/screenshots/`, and imports both designs through the Figma
mock. Run it after layout or capture changes, and compare the screenshots
with the imports.

## Plugin development

1. `npm run watch` in `figma-plugin/`.
2. Figma desktop → **Plugins → Development → Import plugin from manifest…** →
   `figma-plugin/manifest.json` (once).
3. Run `export` from the repo root, then open the plugin and drop
   `build/flutter2figma/design.json`.
4. Debug output: **Plugins → Development → Open console**. Figma API errors
   usually name the property that was set in the wrong order.

Every import creates a new page, so re-importing is safe. Variables, text
styles and effect styles are shared across imports. They are matched by name
and updated in place. Components live in a `Components` frame on each
import's page. Each layer stores
`{origin, source, role}` under the plugin data key `flutter2figma`. To check
where a layer came from, select it and run this in the console:

```js
JSON.parse(figma.currentPage.selection[0].getPluginData('flutter2figma'))
```

### Ordering rules the importer relies on

1. Create the node and set `layoutMode` and paint properties.
2. `appendChild` to the parent.
3. Set `layoutPositioning` (ABSOLUTE needs an auto-layout parent).
4. `resize` **only** if the spec has fixed dimensions. Resizing a text node
   resets `textAutoResize`.
5. Set `layoutSizingHorizontal`/`Vertical`.
6. `minWidth`/`minHeight`, then the children.
7. Place `position`ed children once the parent's size is known
   (`placeAbsoluteChildren`).

Fonts load before any node is created (`loadFonts`). Missing fonts fall back to
the nearest weight in the same family, then to Inter. Substitutions are shown
in the plugin UI.

## Design system recipes

- **A value should bind to a token but doesn't.** Check its `token` in
  `ir.json`. Tokens come from provenance, so the value has to be reached
  through the theme (`MaterialTheme.color`, `theme.textStyle`) or through a
  project constant. For text, the final typography must equal the claimed
  style. Any font, size, weight, height or spacing override drops the token,
  by design.
- **Adding a component.** Set `instance: IrInstanceRef('Name', {...props})` in
  the widget's handler, and only when the output has a stable structure. For
  example, buttons are marked only when their content is a label. Add the name
  to `builtInComponents` if it should be a component even when used once.
- **Adding a token type** (e.g. spacing):
  - add it to `IrDesignSystem`, tagged on the nodes that use it;
  - add it to the renderer's `designSystem` section and to `design.ts`;
  - upsert it in `design-system.ts` and bind it in `importer.ts`;
  - add the new API to the mock, with Figma's validation rules.

## Debugging recipes

| Symptom | Where to look |
| --- | --- |
| Widget shows as `⚠ Unresolved: …` | `analyze --json`: the value is an `UnknownValue`. Usually a method call returns the widget (`buildHeader()`), which isn't followed yet. |
| Wrong color or size value | `analyze --json`: check whether the `RefValue` has `resolved` (or the `CallValue` has `result`). If not, the declaration isn't `const`, isn't in the project, or has no single return expression. |
| Wrong fixed/hug/fill | `build/flutter2figma/ir.json`: follow `width`/`height` down from the screen and apply the sizing checklist. |
| Layer missing after folding | Look at the node's `origin` in `ir.json`; folded widgets are listed there. Folding rules: `simplify.dart`. |
| Figma warns or rejects a combination | `design.json` → `diagnostics`; the renderer logs each downgrade. |
| Two occurrences didn't share a component variant | Compare their `signature()` (in `component_extractor.dart`). Any non-text difference, including an inner sizing mode, makes a separate variant. |
| Plugin throws in Figma but tests pass | The mock is missing that rule. Add it to `figma-mock.ts` first, reproduce, then fix. |
| Analyzer errors: `uri_does_not_exist` for `package:flutter` | Run `fvm flutter pub get` in the target app. |

## Gotchas

- **`package:analyzer` 14.x is mid-migration.**
  - Some APIs are marked `@ToBeDeprecated` or `@experimental`, e.g.
    `ArgumentList.arguments` vs `arguments2`.
  - Class members are under `ClassDeclaration.body.members` and the name is
    `namePart.typeName`.
  - Named arguments are `NamedArgument` (there is no `NamedExpression`).
  - Expect breaking changes when upgrading, and upgrade on purpose.
- **`MaterialApp.theme` is not what widgets render with.** Font sizes and line
  heights are only merged in by `Theme.of(context)`, through `ThemeData.localize`.
  That is why the ground truth reads `Theme.of` inside the app.
- **Pin `material_color_utilities` to the SDK's version**, which is 0.13.0 in
  `packages/flutter/pubspec.yaml`. Otherwise `fromSeed` colors drift. Bump it
  together with `.fvmrc`.
- **`TextTheme.apply(displayColor:)`** covers display\* and
  headlineLarge/Medium only; `headlineSmall` takes `bodyColor`. This is a
  Flutter quirk that we mirror.
- **The plugin `id` in `manifest.json` must be issued by Figma**
  (Plugins → Development → New plugin). Figma rejects made-up IDs with
  "invalid id". The mock doesn't validate IDs, so only a real import catches
  this. Keep the current ID: the Community listing is tied to it.
- **TypeScript 7** doesn't pick up `@figma/plugin-typings` through `typeRoots`.
  `tsconfig.json` lists it under `types`.
- **Node 21's `node --test`** doesn't accept a directory, so the npm script
  names the test file.
- **`.fvmrc` pins the `stable` channel**, not an exact version. After a Flutter
  upgrade:
  - re-run the theme ground truth;
  - regenerate the baseline scheme tables in `material_theme.dart` from
    `theme_data.dart`. Don't edit them by hand.

## Conventions

- **Match Flutter's behaviour, not a guess.** Take defaults from the pinned
  SDK source, and write the layout rules the way Flutter's constraints behave.
- **Never fail silently.** Unknown input becomes a placeholder or
  pass-through, plus an `IrDiagnostic` with a source location.
- **Layers stay independent.** Nothing in `ir/` or `figma/` may import
  analyzer or compiler code. Nothing in `compiler/` may know about Figma.
- **Commits:** imperative subject; the body explains why.
