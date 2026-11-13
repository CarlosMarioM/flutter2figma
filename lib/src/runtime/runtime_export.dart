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
    this.theme,
  });

  final Map<String, IrScreen> screens;
  final Map<String, IrImageAsset> images;
  final List<IrDiagnostic> diagnostics;

  /// Screens Flutter didn't render, and why: they are exported from the
  /// code alone.
  final Map<String, String> fallbacks;

  /// The theme the screens rendered with (`Theme.of`, see `harness.dart`),
  /// or null when none rendered.
  final Map<String, Object?>? theme;
}

/// Why a screen is static, as a category plus one concrete fix.
class FallbackExplanation {
  const FallbackExplanation(this.category, this.cause, this.hint);

  /// Short group title, e.g. "Needs constructor arguments".
  final String category;

  /// One-line cause, shared by the whole category.
  final String cause;

  /// What to change in the app or in test/flutter2figma_setup.dart.
  final String hint;
}

const _setupFile = 'test/flutter2figma_setup.dart';

/// Category of [FallbackExplanation] for errors nothing matched.
const unknownFallbackCategory = 'Unknown error';

/// Matches a raw fallback [reason] (see [RuntimeScreens.fallbacks]) to a
/// known cause and fix. Unknown reasons keep the raw error (first line).
FallbackExplanation explainFallback(String reason) {
  final r = reason.trim();
  bool has(String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(r);
  if (r == 'it needs constructor arguments') {
    return const FallbackExplanation(
      'Needs constructor arguments',
      'the constructor takes arguments that can\'t be made up',
      'Build it in buildScreen in $_setupFile.',
    );
  }
  if (RegExp(r'^(main\(\)|setUp|The app has no|flutter test)').hasMatch(r)) {
    return const FallbackExplanation(
      'The app didn\'t start in a test',
      'main() or setUp threw before the screens could draw',
      'Set things up (mocks, fake services) in setUp in $_setupFile.',
    );
  }
  if (has(r'Navigator')) {
    return const FallbackExplanation(
      'Missing Navigator',
      'the screen uses Navigator without a route above it',
      'Wrap it in a MaterialApp or Navigator in wrapScreen in $_setupFile.',
    );
  }
  if (has(
    r'MissingPluginException|PlatformException|MissingPlatformDirectory|'
    r'platform channel',
  )) {
    return const FallbackExplanation(
      'Plugin or platform channel',
      'a plugin called native code, which tests don\'t have',
      'Mock the plugin\'s channel (setMockMethodCallHandler) or its service '
          'in setUp in $_setupFile.',
    );
  }
  if (has(
    r'ProviderNotFound|Could not find the correct Provider|'
    r'BlocProvider\.of\(\)|No ProviderScope|Bad state: No .*found',
  )) {
    return const FallbackExplanation(
      'Provider or bloc not found',
      'the screen reads a provider/bloc no ancestor gives it',
      'Provide it in wrapScreen in $_setupFile.',
    );
  }
  if (has(r'TimeoutException|timed out|pumpAndSettle')) {
    return const FallbackExplanation(
      'Timed out',
      'the screen never settled (endless animation, pending request)',
      'Fake the slow call or stop the animation in setUp in $_setupFile.',
    );
  }
  final line = r.split('\n').first.trim();
  return FallbackExplanation(
    unknownFallbackCategory,
    line.length > 120 ? '${line.substring(0, 117)}...' : line,
    'Run with -v for the full error, and fix it or work around it in '
    '$_setupFile.',
  );
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
  return RuntimeScreens(
    screens,
    converter.images,
    fallbacks: fallbacks,
    theme: capture.screens.firstOrNull?.theme,
    [
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
    ],
  );
}
