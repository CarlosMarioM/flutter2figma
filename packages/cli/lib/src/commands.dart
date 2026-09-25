import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter2figma_analyzer/flutter2figma_analyzer.dart';
import 'package:flutter2figma_compiler/flutter2figma_compiler.dart';
import 'package:flutter2figma_figma/flutter2figma_figma.dart';
import 'package:flutter2figma_ir/flutter2figma_ir.dart';
import 'package:path/path.dart' as p;

CommandRunner<int> buildRunner() =>
    CommandRunner<int>(
        'flutter2figma',
        'Convert Flutter UIs into editable Figma designs.',
      )
      ..addCommand(AnalyzeCommand())
      ..addCommand(ExportCommand());

abstract class _ProjectCommand extends Command<int> {
  String get projectPath {
    final rest = argResults!.rest;
    if (rest.length > 1) usageException('Expected at most one project path.');
    return rest.isEmpty ? '.' : rest.single;
  }

  Future<ProjectAnalysis> analyzeProject() async {
    stdout.writeln('Analyzing ${p.normalize(p.absolute(projectPath))}...');
    return FlutterProjectAnalyzer(projectPath).analyze();
  }

  void printDiagnostics(
    List<IrDiagnostic> diagnostics, {
    required bool verbose,
  }) {
    final shown = verbose
        ? diagnostics
        : diagnostics.where((d) => d.severity != IrSeverity.info).toList();
    if (shown.isEmpty) return;
    stdout.writeln();
    for (final d in shown) {
      stdout.writeln(
        '  ${d.severity.name.padRight(7)} ${d.message}'
        '${d.source == null ? '' : '  (${d.source})'}',
      );
    }
    final hidden = diagnostics.length - shown.length;
    if (hidden > 0) {
      stdout.writeln('  ($hidden info messages hidden, use --verbose)');
    }
  }
}

class AnalyzeCommand extends _ProjectCommand {
  AnalyzeCommand() {
    argParser.addFlag('json', help: 'Print the analyzed widget trees as JSON.');
  }

  @override
  String get name => 'analyze';

  @override
  String get description =>
      'Discover screens and widgets in a Flutter project.';

  @override
  String get invocation => '${runner!.executableName} analyze [project]';

  @override
  Future<int> run() async {
    final analysis = await analyzeProject();
    if (argResults!.flag('json')) {
      stdout.writeln(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({for (final w in analysis.widgets) w.name: w.tree?.toJson()}),
      );
      return 0;
    }

    final stats = _Stats();
    for (final s in analysis.screens) {
      stats.visit(s.tree);
    }
    stdout
      ..writeln()
      ..writeln('Project: ${analysis.name}')
      ..writeln()
      ..writeln('Dart files:        ${analysis.files.length}')
      ..writeln('Widget classes:    ${analysis.widgets.length}')
      ..writeln('Screens:           ${analysis.screens.length}')
      ..writeln('Widgets analyzed:  ${stats.widgets}')
      ..writeln('Colors:            ${stats.colors.length}')
      ..writeln('Text styles:       ${stats.textStyles}');
    for (final s in analysis.screens) {
      stdout.writeln('  • ${s.name}  (${s.source})');
    }
    printDiagnostics([
      for (final d in analysis.diagnostics) IrDiagnostic(IrSeverity.error, d),
    ], verbose: true);
    stdout
      ..writeln()
      ..writeln('✓ Analysis complete');
    return 0;
  }
}

class ExportCommand extends _ProjectCommand {
  ExportCommand() {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output directory.',
        defaultsTo: 'build/flutter2figma',
      )
      ..addOption(
        'screen-size',
        help: 'Screen frame size as WIDTHxHEIGHT.',
        defaultsTo: '390x844',
      )
      ..addFlag('verbose', abbr: 'v', help: 'Show info diagnostics.');
  }

  @override
  String get name => 'export';

  @override
  String get description =>
      'Export screens to design.json for the Flutter2Figma Figma plugin.';

  @override
  String get invocation => '${runner!.executableName} export [project]';

  @override
  Future<int> run() async {
    final size = RegExp(
      r'^(\d+(?:\.\d+)?)x(\d+(?:\.\d+)?)$',
    ).firstMatch(argResults!.option('screen-size')!);
    if (size == null) usageException('--screen-size must look like 390x844');

    final analysis = await analyzeProject();
    stdout.writeln('Building intermediate representation...');
    final ir = FlutterCompiler(
      screenWidth: double.parse(size.group(1)!),
      screenHeight: double.parse(size.group(2)!),
    ).compile(analysis);

    stdout.writeln('Generating Figma document...');
    final design = FigmaRenderer().render(ir);

    final out = Directory(argResults!.option('output')!)
      ..createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    final irFile = File(p.join(out.path, 'ir.json'))
      ..writeAsStringSync(encoder.convert(ir.toJson()));
    final designFile = File(p.join(out.path, 'design.json'))
      ..writeAsStringSync(encoder.convert(design));

    var nodes = 0;
    void count(IrNode n) {
      nodes++;
      if (n is IrFrame) n.children.forEach(count);
    }

    for (final s in ir.screens) {
      count(s.root);
    }

    printDiagnostics([
      for (final d in (design['diagnostics'] as List))
        IrDiagnostic.fromJson(d as Map<String, Object?>),
    ], verbose: argResults!.flag('verbose'));
    stdout
      ..writeln()
      ..writeln('✓ Export complete')
      ..writeln()
      ..writeln('  ${ir.screens.length} screens')
      ..writeln('  $nodes nodes')
      ..writeln()
      ..writeln(
        '  ${p.relative(designFile.path)}   ← import with the Figma plugin',
      )
      ..writeln('  ${p.relative(irFile.path)}');
    return 0;
  }
}

class _Stats {
  var widgets = 0;
  var textStyles = 0;
  final colors = <String>{};

  void visit(DartValue? v) {
    switch (v) {
      case ObjectValue():
        if (v.isWidget) widgets++;
        if (v.type == 'TextStyle') textStyles++;
        if (v.type == 'Color') {
          colors.add(v.positional.firstOrNull?.toJson().toString() ?? '');
        }
        v.positional.forEach(visit);
        v.named.values.forEach(visit);
        visit(v.build);
      case RefValue():
        if (v.path.first == 'Colors') colors.add(v.dotted);
      case ListValue():
        v.items.forEach(visit);
      case CallValue():
        visit(v.target);
        v.positional.forEach(visit);
        v.named.values.forEach(visit);
      case AccessValue():
        visit(v.target);
      case ConditionalValue():
        visit(v.then);
        visit(v.otherwise);
      case FunctionValue():
        visit(v.returns);
      default:
        break;
    }
  }
}
