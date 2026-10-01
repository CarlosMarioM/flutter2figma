# `design.json` format (version 2)

`design.json` is what `flutter2figma export` writes and the Figma plugin
imports. It describes Figma nodes in Figma Plugin API vocabulary:
`layoutMode`, `layoutSizingHorizontal`, `primaryAxisAlignItems`, …. An
importer can therefore mostly assign properties as they are.

- **Producer:** `lib/src/figma/renderer.dart`.
- **Consumer types:** `figma-plugin/src/design.ts`.
- **Example:** `test/goldens/basic.design.json`, the export of `example/`,
  checked by both test suites.

`ir.json`, written next to it, is the framework-independent intermediate
representation. Its model is documented in the API docs of
`package:flutter2figma/ir.dart`.

## Versioning

| Field | Meaning |
| --- | --- |
| `format` | Always `"flutter2figma/design"`. |
| `version` | Format version, currently `2`. It is bumped when a change would break an existing importer. Importers must reject versions newer than they know; the plugin does. |
| `generator` | `{ "name": "flutter2figma", "version": "<package version>" }`, for diagnostics only. |

Version 1 had no design system, generator, paint variables, text or effect
style references, or instances. The plugin still imports it.

## Top level

```jsonc
{
  "format": "flutter2figma/design",
  "version": 2,
  "generator": { "name": "flutter2figma", "version": "0.1.0" },
  "name": "my_app",                     // the Flutter package name
  "fonts": [{ "family": "Inter", "style": "Bold" }, …],  // every font used, to load first
  "designSystem": { … },                // optional; see below
  "screens": [ <FRAME>, … ],            // top-level frames, placed left to right
  "diagnostics": [
    { "severity": "warning", "message": "…", "source": "lib/home.dart:12" }
  ]
}
```

`fonts` uses Figma style names (`Regular`, `Medium`, `SemiBold`, `Bold`,
`Italic`, `Bold Italic`, …). It covers text nodes and text styles. Load
every font before creating text.

## Nodes

All nodes share these fields:

| Field | Type | Notes |
| --- | --- | --- |
| `type` | `"FRAME"` \| `"TEXT"` | |
| `name` | string | Layer name. |
| `layoutSizingHorizontal`, `layoutSizingVertical` | `"FIXED"` \| `"HUG"` \| `"FILL"` | Never `HUG` on a `layoutMode: "NONE"` frame. Never `FILL` inside a parent that hugs on that axis. The renderer downgrades both and adds a diagnostic. |
| `width`, `height` | number | Present only for `FIXED` axes. |
| `x`, `y` | number | Screens only (their canvas position). |
| `layoutPositioning` | `"ABSOLUTE"` | Set for absolute children of an auto-layout parent, e.g. a floating action button. |
| `position` | `{left?, top?, right?, bottom?}` | Insets inside the parent. Used for children of `NONE` frames (Stack) and for absolute children. Resolve them after the parent has its size. |
| `fills` | Paint[] | See [Paints](#paints). |
| `instance` | `{component, variant, props?}` | Marks a component occurrence. See [Components](#components). |
| `pluginData` | `{origin?, source?, role?}` | Provenance. `origin` lists the Flutter widgets folded into this node, outermost first, e.g. `["Padding", "Column"]`. `source` is `"lib/file.dart:line"`. `role` is a hint: `screen`, `app-bar`, `button`, `tap-target`, `card`, `icon`, `image`, `placeholder`, `grid`, `switch`, `checkbox`, `radio`, `text-field`, `progress`. |

### `FRAME`

| Field | Notes |
| --- | --- |
| `layoutMode` | `"VERTICAL"`, `"HORIZONTAL"` (auto layout) or `"NONE"` (absolute children). |
| `primaryAxisAlignItems` | `MIN` \| `CENTER` \| `MAX` \| `SPACE_BETWEEN`. Auto layout only. |
| `counterAxisAlignItems` | `MIN` \| `CENTER` \| `MAX` \| `BASELINE`. Auto layout only. |
| `itemSpacing`, `paddingTop/Right/Bottom/Left` | Auto layout only. |
| `minWidth`, `minHeight` | Optional; auto layout only. |
| `strokes`, `strokeWeight`, `strokeAlign` | Optional; `strokeAlign` is `"INSIDE"`. |
| `cornerRadius` or `topLeftRadius`… | A uniform radius, or four corners. |
| `effects` | Drop shadows, Figma `DropShadowEffect` shape. |
| `effectStyle` | Optional effect style name the `effects` came from, e.g. `"Elevation/level1"`. Prefer applying the style. |
| `clipsContent` | boolean |
| `children` | Node[] in paint order. |

### `TEXT`

| Field | Notes |
| --- | --- |
| `characters` | The text. Values that are only known at runtime appear as `{name}`. |
| `fontName` | `{family, style}`, one of `fonts`. |
| `fontSize` | number |
| `lineHeight` | `{unit: "PIXELS", value}` or `{unit: "AUTO"}`. |
| `letterSpacing` | `{unit: "PIXELS", value}` |
| `textStyle` | Optional text style name, e.g. `"TextTheme/bodyMedium"`. Present only when the typography above matches that style exactly. |
| `textAlignHorizontal` | `LEFT` \| `CENTER` \| `RIGHT` \| `JUSTIFIED` |
| `textAutoResize` | `"WIDTH_AND_HEIGHT"` (hug) or `"HEIGHT"` (fixed or fill width). |
| `maxLines` | Optional; truncate with an ellipsis. |

## Paints

```jsonc
{ "type": "SOLID", "color": { "r": 0.0, "g": 0.41, "b": 0.43 }, "opacity": 1,
  "variable": "ColorScheme/primary" }   // optional
```

`color` is RGB in 0..1, and alpha is in `opacity`. When `variable` is
present, bind the paint's color to that color variable and keep `opacity`.
So `onSurface` at 38% stays bound to `onSurface`. `variable` is not a Figma
paint key: remove it before assigning the paint.

## Design system

```jsonc
"designSystem": {
  "collection": "my_app theme",      // variable collection name
  "modes": ["Light", "Dark"],        // or a single mode
  "activeMode": "Light",             // the mode the screens were exported in
  "variables": [
    { "name": "ColorScheme/primary", "type": "COLOR",
      "values": { "Light": {"r":…,"g":…,"b":…,"a":1}, "Dark": {…} } },
    { "name": "AppColors/brand", … }  // painted project constants
  ],
  "textStyles": [
    { "name": "TextTheme/bodyMedium", "fontName": {…}, "fontSize": 14,
      "lineHeight": {…}, "letterSpacing": {…} }
  ],
  "effectStyles": [
    { "name": "Elevation/level1", "effects": [ <DropShadowEffect>, … ] }
  ],
  "components": [
    { "name": "Button",
      "source": "lib/…",             // project widgets only
      "variants": [
        { "key": "Button[Type=Filled, State=Enabled]",
          "name": "Type=Filled, State=Enabled", "uses": 2 }
      ] }
  ]
}
```

- **Names** use `/` for Figma grouping. Importers should match existing
  variables and styles by name, so that re-importing updates them instead of
  duplicating them.
- **Modes:** set each screen's explicit mode to `activeMode`.
- **Text styles** carry typography only. Text color is a paint on the node.

## Components

A node with `instance` is an occurrence of a component variant. Its
subtree is complete, so an importer without component support can render it
as a plain frame.

- **Same variant, same structure.** All occurrences with the same
  `instance.variant` key have identical subtrees except for text
  `characters`. So an importer can build the master from the first
  occurrence (`createComponentFromNode`), create instances for the others,
  and apply text overrides by walking both trees in parallel.
- **Size and position are per occurrence.** An occurrence's own sizing and
  placement (`layoutSizing*`, `width`/`height`, `position`) can differ from
  the master's; apply them to the instance.
- **Variants.** `props` (e.g. `{"Type": "Filled", "State": "Enabled"}`) give
  the variant's properties. A variant `name` of `"Prop=Value, …"` is ready
  for `combineAsVariants`. An empty name means a component without variants.
