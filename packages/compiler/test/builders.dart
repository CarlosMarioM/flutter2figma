import 'package:flutter2figma_analyzer/flutter2figma_analyzer.dart';
import 'package:flutter2figma_compiler/flutter2figma_compiler.dart';
import 'package:flutter2figma_ir/flutter2figma_ir.dart';

// Builders for analyzer output, so compiler tests don't need a Flutter SDK.

ObjectValue w(
  String type, {
  String? ctor,
  Map<String, DartValue> named = const {},
  List<DartValue> positional = const [],
}) => ObjectValue(
  type: type,
  constructor: ctor,
  library: 'package:flutter/src/widgets/$type.dart',
  isWidget: true,
  named: named,
  positional: positional,
);

ObjectValue v(
  String type, {
  String? ctor,
  Map<String, DartValue> named = const {},
  List<DartValue> positional = const [],
}) => ObjectValue(
  type: type,
  constructor: ctor,
  library: 'package:flutter/src/painting/$type.dart',
  named: named,
  positional: positional,
);

LiteralValue lit(Object? value) => LiteralValue(value);
RefValue ref(String dotted, {DartValue? resolved}) =>
    RefValue(dotted.split('.'), resolved: resolved);
ListValue list(List<DartValue> items) => ListValue(items);
ObjectValue text(String s, {DartValue? style}) =>
    w('Text', positional: [lit(s)], named: {'style': ?style});
ObjectValue gap(double h) => w('SizedBox', named: {'height': lit(h)});

IrFrame screen(DartValue body, {DartValue? appBar}) {
  final compiler = FlutterCompiler();
  return compiler
      .compileScreen(
        'Test',
        w('Scaffold', named: {'body': body, 'appBar': ?appBar}),
        null,
      )
      .root;
}

IrNode body(DartValue widget) => screen(widget).children.single;

/// Compiles a two-class project: `App` (a MaterialApp) and `Home` (a screen).
IrDocument compileApp(
  Map<String, DartValue> app,
  DartValue body, {
  ThemeBrightness? brightness,
  FlutterCompiler? compiler,
}) => (compiler ?? FlutterCompiler(brightness: brightness)).compile(
  ProjectAnalysis(
    name: 'test',
    root: '.',
    files: const [],
    diagnostics: const [],
    widgets: [
      WidgetClass(
        name: 'App',
        source: 'lib/app.dart:1',
        tree: w('MaterialApp', named: app),
      ),
      WidgetClass(
        name: 'Home',
        source: 'lib/home.dart:1',
        tree: w('Scaffold', named: {'body': body}),
      ),
    ],
  ),
);
