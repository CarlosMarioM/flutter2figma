## Unreleased

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
- `a ?? b` is evaluated: a known `a` decides, and an `a` only known at
  runtime is assumed null as on the first frame, so the fallback shows
  (`Text(icon ?? '')` on an empty board) instead of `{icon ?? ''}`.
- Fields of project enum constants and other project values passed
  positionally are readable: `DrawnElement.cross.icon` gives `❌`.
- New dependency: `image`, to scale and convert images.
- `design.json` version 3 (adds `VECTOR` nodes, `images` and image paints)
  and IR version 3. Update the Figma plugin to import them.

### Tests
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
