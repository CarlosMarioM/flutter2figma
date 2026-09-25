/// Compiles analyzed Flutter widget trees into Flutter2Figma IR.
library;

export 'src/color_scheme.dart' show seedColorScheme, completeColorScheme;
export 'src/compiler.dart' show FlutterCompiler;
export 'src/evaluator.dart' show ValueEvaluator, ColorSchemeValue;
export 'src/material_theme.dart';
export 'src/simplify.dart';
export 'src/text_style.dart';
export 'src/theme_extractor.dart';
