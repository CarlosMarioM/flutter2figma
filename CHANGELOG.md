## Unreleased

### Figma plugin
- The plugin's window shows its version, and so does the import
  notification, so several installed copies can be told apart.
- "Update the plugin" messages point to Figma Community first, with the
  GitHub release as the fallback.

### Export
- The end-of-export summary says which plugin version the file needs.

## 0.4.0

**`flutter2figma export` now runs the app by default** (runtime mode) and
writes `preview.html`. It used to only read the code, which leaves
placeholders wherever the app decides things at runtime. For the old
behavior, use `--static` (for example on CI machines without Flutter).

### Export
- In a Flutter app, plain `flutter2figma` runs the export (export options
  work too: `flutter2figma --static`).
- The export ends with a summary: how many screens Flutter rendered, which
  ones came from the code alone and why, how to fix them, and the next
  steps (check the preview, import in Figma, where to get the plugin).
- Runtime mode falls back to static instead of failing when Flutter isn't
  installed or the project isn't a resolved Flutter app.
- `--[no-]preview` is on by default.

### Figma plugin
- After an import, the plugin names the screens exported from the code
  alone, which may show placeholders, and how to export them exactly.
- Importing a `design.json` from a newer flutter2figma says so and links to
  the latest plugin; the import still goes ahead. The plugin stays offline:
  it compares its version with the one that wrote the file.
- Each release opens a "Publish X.Y.Z to Figma Community" issue with the
  steps and the version note, since Figma has no publishing API.

## 0.3.0

`design.json` is now version 4 (rotation, vector strokes and image fills,
background blurs): update the Figma plugin to import it.

### Preview
- `export --preview` writes `preview.html`: every screen drawn from
  `design.json` in the browser beside Flutter's own render (with
  `--runtime`), a wipe slider between them, and layer outlines by kind
  (vector, text, image). The app's fonts are embedded.

### Export
- Radial and sweep gradients on frames that fill or hug kept the shape of a
  1 px box in Figma (the angle of a sweep was wrong); they now use the size
  they were painted at.
- `--no-auto-layout` keeps runtime screens absolutely positioned.

### Runtime mode
- Custom painters export as vectors: rects, rounded rects, circles, ovals,
  arcs, lines and paths, with their fills and strokes, in paint order. A
  gradient fills its shape as an image; blurs, shadows, blend modes and text
  are drawn alone as images where they paint, and text keeps its rotation.
- `Transform.rotate` is kept: rotated widgets keep their own size and turn
  in Figma, instead of an unrotated bounding box.
- `SweepGradient` becomes a Figma angular gradient, and `BackdropFilter`
  blurs become background blurs.
- Apps with plugins start in more cases: every Pigeon plugin call gets an
  empty answer, and Firebase (core and Remote Config), `package_info_plus`
  and `path_provider` get fakes. Assets the pubspec lists but that are
  missing (a gitignored `.env`) are stood in for during the run, with the
  keys the app reads from `dotenv`.
- Shadows render as shadows (tests draw them as black outlines), and text
  with no font family uses Roboto instead of the test font's boxes.

## 0.2.0

flutter2figma is now labeled **beta**.

### Runtime mode
- `flutter2figma export --runtime` (and `exportProject(runtime: true)`)
  renders each screen with Flutter in a `flutter test` and exports exactly
  what it draws: Flutter's positions, text with its real styles, icons as
  vectors, images, and anything custom-painted as images. Colors and text
  styles are bound to the theme's variables and styles.
- The app starts through its own `main()`. Route-level providers are carried
  to every screen, wrapper classes are used, simple required constructor
  arguments get placeholders, and `shared_preferences` /
  `flutter_secure_storage` get in-memory fakes. `test/flutter2figma_setup.dart`
  can add `setUp`, `wrapScreen` and `buildScreen`.
- Screens that can't run fall back to static export, with the reason.
- Children are recorded in the order they are painted, and what a widget
  paints itself is split into what goes under and over its children, so
  backgrounds, outlines and borders stack as in the app.
- Layout overflows in the app are reported with their `file:line` (the
  screen is still exported).
- `--screenshots <dir>` saves Flutter's own render of every screen, to
  compare with the Figma import.

### Export
- Tap targets: buttons, icon buttons, switches, checkboxes and radios take the
  48 px space Flutter lays them out in (`MaterialTapTargetSize.padded`), so
  the layout around them matches the app. Buttons sit in a `Tap target`
  frame; `materialTapTargetSize` in the theme and `tapTargetSize` in a
  button's style are honored.
- Icons are exact vectors: `Icons.*` glyphs are read from the Material icons
  font of the project's Flutter SDK, and `CupertinoIcons` from the
  `cupertino_icons` package, placed where Flutter draws them and colored by
  the theme's icon color variable. Icons from other fonts stay placeholders.
- Asset images are embedded: `Image.asset`, `Image(image: AssetImage(...))`,
  `DecorationImage` and `SvgPicture.asset` (flutter_svg). The highest
  resolution variant (`2.0x/`, `3.0x/`) is used at its logical size, `fit`
  maps to Figma's scale modes, and images over Figma's 4096 px limit are
  scaled down (other formats such as WebP become PNG). Network, file and
  memory images stay placeholders.
- `ListTile`, `SwitchListTile`, `CheckboxListTile` and `RadioListTile`:
  Material 3 padding, heights (one, two and three lines, dense), leading
  slot, text styles and selected/disabled colors.
- Chips (`Chip`, `InputChip`, `FilterChip`, `ChoiceChip`, `ActionChip`,
  elevated variants): outline or tonal fill, avatar, checkmark when selected,
  delete icon, tap target.
- `NavigationBar` and `BottomNavigationBar` in `Scaffold.bottomNavigationBar`:
  the body fills the space above the bar and a floating action button sits
  above it.
- `Wrap` wraps (Figma auto layout wrap) instead of exporting as a row.
- Gradients: `LinearGradient` and `RadialGradient` become Figma gradient
  fills (colors, stops, direction, center and radius) in both modes,
  instead of their first color.
- `CircleAvatar` (color, child, background image).
- A frame downgraded from fill to hug no longer leaves filling children
  inside it, which Figma rejected; a decorated `Container` with a margin
  grows with a filling child, as in Flutter.
- `a ?? b` is evaluated: a known `a` decides, and an `a` only known at
  runtime is assumed null as on the first frame, so the fallback shows
  (`Text(icon ?? '')` on an empty board) instead of `{icon ?? ''}`.
- Fields of project enum constants and other project values passed
  positionally are readable: `DrawnElement.cross.icon` gives `❌`.
- New dependency: `image`, to scale and convert images.
- `design.json` version 3 (adds `VECTOR` nodes, `images` and image paints)
  and IR version 3. Update the Figma plugin to import them.

### Tests
- `showcase/`, a dense multi-screen app, and `tool/stress.sh`, which exports
  it both ways and imports both through the Figma mock. CI exports it too.
- The example app measures real Flutter layout sizes
  (`test/goldens/basic_layout.json`), and the plugin test checks Figma
  produces the same ones.

## 0.1.0

First release.

### Export
- `flutter2figma export` turns a Flutter project into `design.json` (for the
  Figma plugin) and `ir.json` (the intermediate representation).
- Static analysis only: the app is never run. Screens are found through
  wrappers such as providers, `BlocBuilder`, `PopScope` and auth gates.
- Auto layout that follows Flutter's constraints (fixed / hug / fill).
  Wrappers like `Padding` fold into frame padding, and `SizedBox` spacers into
  gaps, but only when the result renders the same.
- Layout, content, Material controls and surfaces, `TextField`, and progress
  indicators. Widgets from packages and `builder:` widgets render their
  content. Anything unsupported becomes a flagged placeholder.
- Runtime-dependent UI exports the initial state where it can be known, and
  reports what it assumed:
  - bloc/cubit builders see the bloc's initial state;
  - constructor defaults are filled in, including freezed `@Default`;
  - conditions on known values are folded;
  - other conditionals keep the richer branch;
  - loops over literal lists are unrolled, and loops over runtime data show
    sample items.
- `GridView`, `Switch`, `Checkbox` and `Radio`, drawn with Material 3
  defaults.

### Theme
- Reads the app's `MaterialApp` `theme`, `darkTheme` and `themeMode`, and
  resolves them the way Flutter does:
  - color schemes, including `ColorScheme.fromSeed`;
  - `fontFamily`, `textTheme` and GoogleFonts;
  - app bar, card and button themes;
  - nested `Theme` widgets.
- Checked against Flutter's own resolved theme on real apps (exact match).
- `flutter2figma theme` prints the resolved theme as JSON.

### Design system
- `ColorScheme` roles become color variables with Light and Dark modes.
  Painted project color constants become variables too.
- Text theme entries become text styles, and elevation levels become effect
  styles. Values bind to these only when they came from them.
- Material buttons become a `Button` component set. Project widgets used
  twice or more become components with instances.

### Figma plugin
- Imports `design.json` (format version 2, documented in
  `doc/design-json.md`). It creates or updates the variable collection,
  variables and styles by name, builds components from first occurrences,
  binds paints to variables, and sets each screen's mode.
- Has no network access.
- Released as `flutter2figma-figma-plugin-<version>.zip` on GitHub Releases.

### API
- `package:flutter2figma/flutter2figma.dart` provides `exportProject()`.
  The stages are separate libraries: `analyzer.dart`, `compiler.dart`,
  `ir.dart` and `figma.dart`.
