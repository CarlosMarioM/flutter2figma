import 'package:flutter2figma/ir.dart';

import '../analyzer/project_analyzer.dart';
import '../compiler/icon_font.dart';
import 'capture_converter.dart';
import 'runtime_capture.dart';

/// Screens Flutter rendered, ready to replace their static versions.
class RuntimeScreens {
  RuntimeScreens(
    this.screens,
    this.images,
    this.diagnostics, {
    this.fallbacks = const {},
  });

  final Map<String, IrScreen> screens;
  final Map<String, IrImageAsset> images;
  final List<IrDiagnostic> diagnostics;

  /// Screens Flutter didn't render, and why: they are exported from the
  /// code alone.
  final Map<String, String> fallbacks;
}

/// Renders [analysis]'s screens with Flutter and converts them. Screens
/// that can't be rendered are left out (and reported), so the caller can
/// export them statically.
Future<RuntimeScreens> renderScreens(
  ProjectAnalysis analysis, {
  List<String>? flutterCommand,
  int width = 390,
  int height = 844,
  Duration timeout = const Duration(minutes: 10),
  String? screenshotsDir,
  bool autoLayout = true,
}) async {
  final capture = await RuntimeCapture(
    analysis.root,
    flutterCommand: flutterCommand,
    width: width,
    height: height,
    timeout: timeout,
    screenshotsDir: screenshotsDir,
  ).run(analysis);
  final converter = CaptureConverter(
    iconFonts: projectIconFonts(analysis.root),
    autoLayout: autoLayout,
  );
  final sources = {for (final w in analysis.screens) w.name: w.source};
  final screens = {
    for (final s in capture.screens)
      s.name: converter.convert(s, source: sources[s.name]),
  };
  final total = analysis.screens.length;
  final names = {for (final s in analysis.screens) s.name};
  // Errors about one screen start with its name; the rest (main() threw,
  // flutter test didn't start) concern them all.
  final general = [
    for (final e in capture.errors)
      if (!names.any((n) => e.startsWith('$n: '))) e,
  ];
  final fallbacks = {
    for (final name in names)
      if (!screens.containsKey(name))
        name: capture.skipped.contains(name)
            ? 'it needs constructor arguments'
            : capture.errors
                      .where((e) => e.startsWith('$name: '))
                      .map((e) => e.substring(name.length + 2))
                      .firstOrNull ??
                  general.firstOrNull ??
                  'Flutter didn\'t render it',
  };
  return RuntimeScreens(screens, converter.images, fallbacks: fallbacks, [
    IrDiagnostic(
      IrSeverity.info,
      'Runtime: ${screens.length} of $total screens rendered by Flutter'
      '${screens.length < total ? '; the others are exported statically' : ''}',
    ),
    for (final e in capture.errors)
      IrDiagnostic(IrSeverity.warning, 'Runtime capture: $e'),
    for (final w in capture.warnings)
      IrDiagnostic(IrSeverity.warning, 'In the app: $w'),
    for (final name in capture.skipped)
      IrDiagnostic(
        IrSeverity.info,
        'Runtime: $name needs constructor arguments that can\'t be made up; '
        'exported statically (build it in test/flutter2figma_setup.dart)',
      ),
  ]);
}
