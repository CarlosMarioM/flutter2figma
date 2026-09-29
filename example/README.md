# flutter2figma example

A small Flutter app to export. It has four screens:
- the reference screen: `lib/home_screen.dart`;
- a profile screen with a reusable `StatCard` widget: `lib/profile_screen.dart`;
- a settings screen with state-dependent UI: loading gate, loops, a builder
  and a text field (`lib/settings_screen.dart`);
- a scoreboard driven by a cubit, exported in its initial state, with a
  grid, a switch and a checkbox (`lib/scoreboard_screen.dart`).

The app's theme (`lib/theme.dart`) uses a seed color, a custom font, and
component themes.

```sh
cd example
flutter pub get
dart pub global activate flutter2figma
flutter2figma export
```

This writes `build/flutter2figma/design.json`; import it with the Figma
plugin. The export contains:
- 4 screens;
- 46 color variables with Light and Dark modes;
- 15 text styles;
- a `Button` component set;
- a `StatCard` component used twice.

From Dart:

```dart
import 'package:flutter2figma/flutter2figma.dart';

Future<void> main() async {
  final result = await exportProject('example');
  print('${result.ir.screens.length} screens');
}
```
