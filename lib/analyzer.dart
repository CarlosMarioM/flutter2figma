/// Static analysis of a Flutter project's widget trees.
///
/// [FlutterProjectAnalyzer] resolves every library under `lib/` with
/// `package:analyzer` and turns what each widget's `build` returns into a
/// tree of [DartValue]s: constructor calls, literals, references and calls.
/// It never runs the app.
///
/// ```dart
/// final analysis = await FlutterProjectAnalyzer('path/to/app').analyze();
/// for (final screen in analysis.screens) {
///   print('${screen.name} (${screen.source})');
/// }
/// ```
///
/// The project must be resolved first (`flutter pub get`).
library;

export 'src/analyzer/project_analyzer.dart';
export 'src/analyzer/values.dart';
