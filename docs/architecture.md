# Architecture

## Contracts between layers

| Boundary | Format | Defined in |
| --- | --- | --- |
| analyzer → compiler | `DartValue` tree (in-memory; `analyze --json` prints it) | `packages/analyzer/lib/src/values.dart` |
| compiler → renderer | IR, `flutter2figma/ir` v1 (`ir.json`) | `packages/ir/lib/src/model.dart` |
| renderer → plugin | `flutter2figma/design` v1 (`design.json`) | `packages/figma/lib/src/renderer.dart`, `figma-plugin/src/design.ts` |

The IR is the stable centre. Adding an HTML/React backend means writing another
renderer over `IrDocument`. Runtime inspection (`--runtime`) would be another
IR producer next to the static compiler.

## Analyzer: values, not execution

`FlutterProjectAnalyzer` resolves `lib/**.dart` with an
`AnalysisContextCollection`, so it needs `.dart_tool/package_config.json`
from `flutter pub get`. For each `StatelessWidget` / `StatefulWidget`
(via `createState` → `State.build`), it takes the last top-level `return` of
`build` and converts the expression:

| Dart | DartValue |
| --- | --- |
| `Container(...)`, `EdgeInsets.all(16)` | `ObjectValue` (type, named ctor, library URI, `isWidget` from the static type) |
| `16`, `'Hi'`, `null`, string interpolation | `LiteralValue` (non-constant interpolations become `{name}`) |
| `Colors.blue`, `kPadding`, `CrossAxisAlignment.start` | `RefValue` + analyzed `const` initializer when there is one |
| `textTheme.bodyLarge`, `color.shade200` | `AccessValue` |
| `Theme.of(context)`, `style.copyWith(...)` | `CallValue` |
| `a ? b : c`, collection `if` | `ConditionalValue` |
| closures | `FunctionValue` (+ single return expression) |
| anything else | `UnknownValue` (source text) |

Local variables in `build` are substituted with their initializers. When a widget declared
in the project is constructed, its `build` is expanded into `ObjectValue.build`,
with call-site arguments bound to fields (`label`, `widget.label`,
`this.label`).

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
