# Architecture

## Contracts between layers

| Boundary | Format | Defined in |
| --- | --- | --- |
| analyzer → compiler | `DartValue` tree (in-memory; `analyze --json` prints it) | `lib/src/analyzer/values.dart` |
| compiler → renderer | IR, `flutter2figma/ir` v3 (`ir.json`) | `lib/src/ir/model.dart` |
| renderer → plugin | `flutter2figma/design` v3 (`design.json`, spec in [design-json.md](design-json.md)) | `lib/src/figma/renderer.dart`, `figma-plugin/src/design.ts` |

The IR is the stable centre. Adding an HTML/React backend means writing another
renderer over `IrDocument`. Runtime inspection (`--runtime`) would be another
IR producer next to the static compiler.

## Analyzer: values, not execution

`FlutterProjectAnalyzer` resolves `lib/**.dart` with an
`AnalysisContextCollection`, so it needs `.dart_tool/package_config.json`
from `flutter pub get`. For each `StatelessWidget` / `StatefulWidget`
(via `createState` → `State.build`), it converts what `build` returns:

| Dart | DartValue |
| --- | --- |
| `Container(...)`, `EdgeInsets.all(16)` | `ObjectValue` (type, named ctor, library URI, `isWidget` from the static type, `inProject`) |
| `16`, `'Hi'`, `null`, string interpolation | `LiteralValue` (non-constant interpolations become `{name}`) |
| `Colors.blue`, `kPadding`, `AppTheme.light`, `CrossAxisAlignment.start` | `RefValue` + `resolved`: any `const` initializer (SDK included), or a project `final`/getter body |
| `textTheme.bodyLarge`, `color.shade200` | `AccessValue` |
| `Theme.of(context)`, `style.copyWith(...)`, `_buildHeader()` | `CallValue` + `result` for project functions and methods (arguments bound to parameters) |
| `a ? b : c`, collection `if`, `switch` expressions (cases chained in order), early returns (`if (x) { return A; } return B;` → `x ? A : B`) | `ConditionalValue` |
| collection `for` over runtime data | `LoopValue` (loop header + body) |
| collection `for` / `.map((x) => …)` over a literal list | unrolled: one value per item, the loop variable bound to it |
| closures | `FunctionValue` (+ what the body returns, same rules as `build`) |
| anything else | `UnknownValue` (source text) |

**Screens.** A widget class is a screen when its `build` leads to a
`Scaffold` along a single-child path. The path can go through `child`,
`builder:` results, project widgets' `build`, conditionals and project calls.
This finds screens wrapped in providers, `BlocBuilder`, `PopScope`, or auth
gates.

`scaffoldPath` records the project widget classes on the way. A class whose
path goes through another screen class is only a wrapper, so it isn't listed.
For conditionals, the branch that builds the `Scaffold` most directly wins, so
`if (done) return OtherScreen(); return Scaffold(...)` is still a screen.

Local variables in `build` are substituted with their initializers. When a widget declared
in the project is constructed, its `build` is expanded into `ObjectValue.build`,
with call-site arguments bound to fields (`label`, `widget.label`,
`this.label`).

Project declarations are indexed by element (`_declKey`): top-level and static
variables, getters, functions and methods. References to them are analyzed
where they are declared:

- **Static and top-level members** are analyzed in a detached scope and cached.
- **Instance members of the widget being expanded** are analyzed in the widget's
  scope, so they see the bound fields. Examples: `_actions()`, `Widget get _header`.
- **Parameters** get the call-site arguments.

Recursion is bounded by the `expanding` set and a depth limit.

## Compiler: theme extraction

`ThemeExtractor` finds the project's `MaterialApp`, picks `theme` or
`darkTheme` (`--brightness`, else a literal `themeMode`), and replays the
Flutter code paths that build what `Theme.of(context)` returns:

| Flutter | Here |
| --- | --- |
| `ThemeData` factory: `colorScheme ?? fromSeed(colorSchemeSeed) ?? baseline` | `_build` |
| `ColorScheme` getters' fallbacks (`surfaceContainerLow ?? surface`, …), `.light()`/`.dark()` defaults | `color_scheme.dart` `completeColorScheme` |
| `ColorScheme.fromSeed` → `DynamicScheme` → `MaterialDynamicColors` | `seedColorScheme` (same `material_color_utilities` version as the SDK) |
| Typography: `onSurface` colors, `fontFamily` applied, user `textTheme` merged | `MaterialTheme.textStyle` |
| `ThemeData.localize`: M3 geometry (sizes, heights) under the theme's styles | geometry `m3TextTheme` merged first |
| `ThemeData.copyWith`, `Theme(data: Theme.of(context).copyWith(...))` | `_copyWith`; the compiler swaps `eval.theme` for the subtree |

Component themes currently applied:
- `scaffoldBackgroundColor`;
- `appBarTheme`: colors, elevation, `centerTitle`, title style, height;
- `cardTheme`: color, elevation, margin, shape;
- the four button themes, applied under the widget's own `style`.

Every other `ThemeData` argument is reported, never silently dropped.

**Ground truth.** `example/test/theme_ground_truth_test.dart` pumps the
app, reads `Theme.of(context)` in light and dark, and writes
`test/goldens/basic_theme.json`.
`theme_extraction_test.dart` requires the static extraction to match that file
exactly: every color role, every text style property, and the component
themes.

## Design system

### Tokens by provenance

The compiler records where a value came from and does not guess from the
value. `IrColor.token`, `IrTextStyle.token` and `IrFrame.shadowToken` are
set as follows:

| Value | Token |
| --- | --- |
| `MaterialTheme.color(role)`: every theme default, `Theme.of(context).colorScheme.x`, and any `ColorScheme` value equal to the ambient one (e.g. a local `colorScheme` inside the theme builder) | `ColorScheme/<role>` |
| A painted color reached through a project `RefValue` (`inProject`) | `AppColors/brand` (single-segment names: `Constants/<name>`) |
| `withOpacity`/`withValues` on a token color | same token; the alpha becomes paint opacity |
| Text: the most specific theme style merged into the text's style | `TextTheme/<name>`, **kept only if the final typography equals that style**; otherwise the first theme style with identical typography, otherwise none. Color is never part of a text style |
| Shadows produced by `theme.shadows(elevation)` | `Elevation/level1..5` |

The `IrDesignSystem` contains:
- every non-deprecated scheme role, with a value per mode;
- the painted project colors;
- the 15 text theme styles;
- the 5 elevation levels.

The modes come from extracting `theme` and `darkTheme` separately. When there
is no `darkTheme`, there is a single mode.

### Components

The compiler marks occurrences with `IrNode.instance` in two places:
- **`_button`:** `Button` with `Type`, `State` and `Icon` props, when the content is a label.
- **`_projectWidget`:** the class name, with no props.

`ComponentExtractor` then groups them:

1. Project widgets with fewer than `minComponentUses` (default 2) occurrences
   are unmarked. Buttons are always components.
2. Occurrences are grouped by their semantic props, then by `signature()`.
   The signature is the node's JSON without text content, provenance, and the
   root's own size and position.
3. A semantic group with more than one signature gets a `Variant=1..n` prop.

So instances of one variant differ **only in text**. The IR keeps each
occurrence's full subtree, so renderers without components can ignore the
markers. `simplify()` never folds outer padding into an occurrence, because
the component's padding must stay its own.

### In Figma (plugin)

1. **Design system upsert (`design-system.ts`).**
   - The variable collection is reused by name. Its default mode is renamed
     to the first mode, and further modes are added. Plan limits are caught
     and reported.
   - Variables and styles are also matched by name, so re-importing updates
     them instead of duplicating them.
2. **Paints.** The `variable` key is stripped from each paint, then the paint
   is bound with `setBoundVariableForPaint`.
3. **Styles.** Text nodes with a `textStyle` use `setTextStyleIdAsync`. Frames
   with an `effectStyle` use `setEffectStyleIdAsync`.
4. **Components.**
   - The first occurrence of a variant is built as ordinary frames, so Figma
     measures its real size.
   - `createComponentFromNode` turns it into the master. An instance is
     inserted in its place.
   - The master is fixed to its measured size and moved into the
     `Components` frame below the screens.
   - Later occurrences are `createInstance()` plus text overrides. The spec
     and instance trees are walked in parallel.
   - Variants with props are combined with `combineAsVariants` into a
     component set.
5. **Mode.** Screens and the library get `setExplicitVariableModeForCollection`
   for the exported mode.

## Compiler: icons and tap targets

**Icons.** `Icons.add` resolves to the SDK constant
`IconData(0xe047, fontFamily: 'MaterialIcons')`. `projectIconFonts()`
(`icon_font.dart`) finds the fonts behind those families through the
project's `package_config.json`: `MaterialIcons-Regular.otf` in the Flutter
SDK's `bin/cache/artifacts/material_fonts/`, and `CupertinoIcons.ttf` in
`cupertino_icons`. `IconFont` reads the `cmap`, the outlines (CFF Type 2
charstrings or TrueType `glyf`) and `hhea` metrics, and places the glyph as
Flutter's `Icon` does: `fontSize: size, height: 1`, centered in a `size`
square. The icon becomes a `NONE` frame holding an `IrVector`, whose path
starts at its exact bounds (curve extremes, not control points) because
Figma sizes vectors the same way. An icon chosen by an unknown condition uses
the `true` branch; an icon from another font is a placeholder.

**Images.** `ProjectAssets` (`image_assets.dart`) resolves asset names as
Flutter's bundle does: relative to the project, `packages/<name>/…` (or a
`package:` argument) through `package_config.json`, picking the highest
`N.Nx/` variant. Its logical size is pixels ÷ ratio. Images Figma can't take
are decoded with `package:image`, scaled to 4096 px and re-encoded. Used
assets are collected into `IrDocument.images` and painted with
`IrFrame.image` (`IrImagePaint`, with its `BoxFit`). `_image` sizes like
`RenderImage`: given dimensions, else the intrinsic size, keeping the aspect
ratio when one side is known; an image stretched across unknown space
estimates the free side from the screen width.

**Tap targets.** Under `MaterialTapTargetSize.padded` (the default), Flutter
lays buttons, icon buttons and selection controls out in at least 48×48
while drawing them smaller. Buttons and icon buttons are wrapped in a
`Tap target` frame (`role: tap-target`, min 48×48, centered); switches,
checkboxes and radios get the padded size directly. `shrinkWrap` in the
theme (`materialTapTargetSize`) or a button style (`tapTargetSize`) turns it
off. `example/test/layout_ground_truth_test.dart` measures the real sizes.

## Compiler: sizing model

Figma auto layout needs each node to be *fixed*, *hug* or *fill* per axis.
Flutter decides size through constraints, so the compiler passes a reduced
constraint set down the tree:

- `force` (tight): the parent dictates this axis, so the child fills it.
- `bounded`: a maximum exists. It is false on a Flex main axis and inside scroll views.

Examples: `Scaffold.body` gets a forced width and a bounded height. A `Column` with
`mainAxisSize.max` in bounded space fills its main axis. `stretch` forces
children across. `Expanded` forces fill on the main axis. `Container` expands
when it has no child or has an `alignment`. After a node is built, a hugging box whose
child fills grows to fill too, as Flutter's `Padding(child: Column())` does.

### Simplification

`simplify()` folds a structural wrapper (`Padding`, `SizedBox`, `Container`,
`Center`, `Align`) into its only child when:

- the wrapper paints nothing (no fill, stroke, shadow or clip);
- padding can move inside a child that paints nothing and has no padding of its own;
- on each axis, the merged size equals the old outer size, and content placement
  doesn't change (both sides start-aligned whenever the child grows).

Layout widgets (`Row`/`Column`/`Stack`) and project widgets are never folded,
so the Figma layer tree keeps the authored hierarchy. The folded widgets are kept
in `origin`, e.g. `["Padding", "Column", "SizedBox"]`.

Equal spacers between every pair of children, `[a, SizedBox(16), b, SizedBox(16), c]`,
become `gap: 16`. `Column(spacing:)` maps to `gap` directly.

### Unknown and runtime-dependent UI

- **Widgets without a handler.** This covers unknown Flutter widgets and all
  package widgets. `_genericWidget` renders the `builder:` callback's result;
  failing that it passes through to `child`, lays out `children` in a column,
  or shows a `⚠` placeholder. Package wrappers are reported as info (usually
  state management with no visuals); unknown Flutter widgets as warnings.
- **Initial state (analyzer).**
  - **Constructor defaults.** Calls to project constructors get the defaults
    of the named parameters they leave out (`_defaults`). This covers
    `{this.x = 1}` and freezed `@Default(1)`, and optional nullables default
    to `null`.
  - **Bloc state.** `BlocBuilder<B, S>` / `BlocConsumer` builders, and
    `context.read/watch<B>().state` / `BlocProvider.of<B>(context).state`,
    see `B`'s initial state: the argument of `super(...)` in `B`'s unnamed
    constructor (`_initialState`).
  - **Folding.** Conditions over known values are folded (`_condition`):
    literals, `!`, `&&`, `||`, `==`/`!=`, `x != null`, field reads on known
    objects, and `.length`/`.isEmpty` of known lists. Folding applies to
    `?:`, collection `if` and `if` statements, and only the branch taken is
    kept.
  - **Result.** Screens render their first frame, not an impossible mix of
    states.
- **Conditionals that stay unknown.** The branch with the most inline
  widgets is exported (`_richness`). Another widget class counts as one widget, so a branch that
  navigates elsewhere doesn't outweigh this screen's own UI. On a tie, the
  `true` branch wins.
- **Loops over runtime data.** Collection `for` and `.map()` / `.toList()` are
  expanded to `listPreviewCount` copies (`_items`).
- **Non-finite values.** `double.infinity` and NaN never reach the output.
  Handlers interpret them (e.g. `Size(double.infinity, 52)` means full width),
  and `_sanitize` replaces any that slip through, with a warning.

## Renderer and plugin rules

Figma constraints the plugin must respect:

1. Set `layoutMode` before `HUG` (HUG needs auto layout, or a text node).
2. Append a node to its parent before setting `FILL` (FILL needs an auto-layout parent).
3. Load the font before setting `fontName` or `characters`.
4. Resize only nodes with fixed dimensions. Resizing a text node would reset its auto-resize.

The renderer never emits FILL inside a parent that hugs on that axis
(Figma would silently make the parent fixed). It never emits HUG on a
`layoutMode: NONE` (Stack) frame. It downgrades either case and warns. Stack
children use `position` (`left/top/right/bottom`), which the plugin turns into
`x/y`, a resize and `constraints` once the parent's size is known.
`FloatingActionButton` uses the same mechanism as an absolute child inside auto
layout.
