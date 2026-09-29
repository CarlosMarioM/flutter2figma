/// The Flutter2Figma intermediate representation (IR).
///
/// A framework-independent description of a UI: frames with auto-layout
/// ([IrFrame]), text ([IrText]), sizing ([IrSizing]), paint and typography,
/// plus the design system ([IrDesignSystem]) the nodes reference.
///
/// Producers (the Flutter compiler in `package:flutter2figma/compiler.dart`)
/// and consumers (the Figma renderer in `package:flutter2figma/figma.dart`)
/// meet here. Every node records the Flutter widgets it came from
/// ([IrNode.origin]) and their `file:line` ([IrNode.source]).
///
/// Serialized as `ir.json` via [IrDocument.toJson] / [IrDocument.fromJson].
library;

export 'src/ir/model.dart';
