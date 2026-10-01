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
Future<ExportResult> exportProject(
  String path, {
  ThemeBrightness? brightness,
  bool designSystem = true,
  int minComponentUses = 2,
  double screenWidth = 390,
  double screenHeight = 844,
}) async {
  final analysis = await FlutterProjectAnalyzer(path).analyze();
  final ir = FlutterCompiler(
    brightness: brightness,
    designSystem: designSystem,
    minComponentUses: minComponentUses,
    screenWidth: screenWidth,
    screenHeight: screenHeight,
    iconFonts: projectIconFonts(analysis.root),
  ).compile(analysis);
  return ExportResult(
    analysis: analysis,
    ir: ir,
    design: FigmaRenderer().render(ir),
  );
}
