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
