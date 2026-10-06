/// Convert a Flutter UI into an editable Figma design.
///
/// Most people use the command-line tool:
///
/// ```sh
/// dart pub global activate flutter2figma
/// flutter2figma export path/to/app
/// ```
///
/// Then import `design.json` with the Flutter2Figma Figma plugin.
///
/// This library is the same pipeline as a Dart API. [exportProject] runs
/// all of it; the stages are available separately in
/// `package:flutter2figma/analyzer.dart`, `compiler.dart`, `ir.dart` and
/// `figma.dart`.
library;

import 'analyzer.dart';
import 'compiler.dart';
import 'figma.dart';
import 'ir.dart';
import 'src/runtime/runtime_export.dart';

export 'src/version.dart' show packageVersion;

/// Everything an export produces.
class ExportResult {
  ExportResult({
    required this.analysis,
    required this.ir,
    required this.design,
  });

  /// The analyzed project: widget classes, screens, diagnostics.
  final ProjectAnalysis analysis;

  /// The intermediate representation (`ir.json`).
  final IrDocument ir;

  /// The Figma document (`design.json`), ready to `jsonEncode`.
  final Map<String, Object?> design;

  /// Problems and approximations, from every stage.
  List<IrDiagnostic> get diagnostics => [
    for (final d in design['diagnostics'] as List)
      IrDiagnostic.fromJson(d as Map<String, Object?>),
  ];
}

/// Analyzes the Flutter project at [path] and renders it for Figma.
///
/// The project must be resolved (`flutter pub get`). See [FlutterCompiler]
/// for the options.
///
/// With [runtime], the screens are rendered by Flutter (`flutter test`) and
/// exported exactly as drawn; this runs the app's `main()`, so only use it
/// on trusted code. Screens that can't run are exported statically.
/// [flutterCommand] is e.g. `['fvm', 'flutter']`, detected when null.
/// Without [autoLayout], runtime screens keep Flutter's positions absolutely
/// instead of becoming auto layout.
Future<ExportResult> exportProject(
  String path, {
  ThemeBrightness? brightness,
  bool designSystem = true,
  int minComponentUses = 2,
  double screenWidth = 390,
  double screenHeight = 844,
  bool runtime = false,
  List<String>? flutterCommand,
  bool autoLayout = true,
}) async {
  final analysis = await FlutterProjectAnalyzer(path).analyze();
  final rendered = runtime
      ? await renderScreens(
          analysis,
          flutterCommand: flutterCommand,
          autoLayout: autoLayout,
          width: screenWidth.round(),
          height: screenHeight.round(),
        )
      : null;
  final compiled =
      FlutterCompiler(
        brightness: brightness,
        designSystem: designSystem,
        minComponentUses: minComponentUses,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
        iconFonts: projectIconFonts(analysis.root),
      ).compile(
        analysis,
        rendered: rendered?.screens ?? const {},
        renderedImages: rendered?.images ?? const {},
        renderedTheme: rendered?.theme,
      );
  final ir = IrDocument(
    project: compiled.project,
    screens: compiled.screens,
    designSystem: compiled.designSystem,
    images: compiled.images,
    diagnostics: [...?rendered?.diagnostics, ...compiled.diagnostics],
  );
  return ExportResult(
    analysis: analysis,
    ir: ir,
    design: FigmaRenderer().render(ir),
  );
}
