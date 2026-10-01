/// Compiles analyzed Flutter widget trees into the IR.
///
/// [FlutterCompiler] resolves the app's Material theme ([ThemeExtractor]),
/// maps widgets to frames and text with a Flutter-like layout model, and
/// extracts the design system: color tokens with Light/Dark values, text and
/// elevation styles, and components ([ComponentExtractor]).
///
/// ```dart
/// final analysis = await FlutterProjectAnalyzer('path/to/app').analyze();
/// final ir = FlutterCompiler().compile(analysis);
/// ```
library;

export 'src/compiler/color_scheme.dart'
    show seedColorScheme, completeColorScheme;
export 'src/compiler/compiler.dart' show FlutterCompiler;
export 'src/compiler/component_extractor.dart';
export 'src/compiler/icon_font.dart' show IconFont, IconGlyph, projectIconFonts;
export 'src/compiler/evaluator.dart' show ValueEvaluator, ColorSchemeValue;
export 'src/compiler/material_theme.dart';
export 'src/compiler/simplify.dart';
export 'src/compiler/text_style.dart';
export 'src/compiler/theme_extractor.dart';
