/// Renders the IR as a Figma design document (`design.json`).
///
/// [FigmaRenderer] maps the IR to Figma Plugin API names and enums
/// (`layoutMode`, `layoutSizingHorizontal`, variables, text and effect
/// styles, components). The Flutter2Figma Figma plugin imports the result.
///
/// ```dart
/// final design = FigmaRenderer().render(ir);
/// File('design.json').writeAsStringSync(jsonEncode(design));
/// ```
library;

export 'src/figma/renderer.dart';
