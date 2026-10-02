import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:flutter2figma/analyzer.dart';
import 'package:flutter2figma/compiler.dart';
import 'package:flutter2figma/figma.dart';
import 'package:flutter2figma/ir.dart';
import 'package:path/path.dart' as p;

import '../runtime/runtime_export.dart';
import '../version.dart';

CommandRunner<int> buildRunner() => _Runner()
  ..addCommand(AnalyzeCommand())
  ..addCommand(ExportCommand())
  ..addCommand(ThemeCommand());

class _Runner extends CommandRunner<int> {
  _Runner()
    : super(
        'flutter2figma',
        'Convert Flutter UIs into editable Figma designs.',
      ) {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the flutter2figma version.',
    );
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.flag('version')) {
      stdout.writeln('flutter2figma $packageVersion');
      return 0;
    }
    return super.runCommand(topLevelResults);
  }
}

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
      ..addOption(
        'brightness',
        help: 'Which app theme to export.',
        allowed: ['auto', 'light', 'dark'],
        allowedHelp: {
          'auto':
              'Follow MaterialApp.themeMode (light unless it is ThemeMode.dark).',
          'light': 'MaterialApp.theme.',
          'dark': 'MaterialApp.darkTheme (falls back to theme).',
        },
        defaultsTo: 'auto',
      )
      ..addFlag(
        'design-system',
        help:
            'Export color variables (per theme mode), text and effect styles, '
            'and components.',
        defaultsTo: true,
      )
      ..addOption(
        'min-component-uses',
        help: 'Uses before a project widget becomes a component.',
        defaultsTo: '2',
      )
      ..addFlag(
        'runtime',
        help:
            'Render the screens with Flutter (flutter test) and export exactly '
            'what it draws. Runs the app\'s main(): use on trusted code. '
            'Screens that cannot run are exported statically.',
      )
      ..addOption(
        'flutter',
        help:
            'Flutter command for --runtime, e.g. "fvm flutter". Detected '
            'when omitted (FVM if the project pins a version).',
      )
      ..addOption(
        'screenshots',
        help:
            'With --runtime: also save Flutter\'s own render of each screen '
            'as PNG in this directory, to compare with the Figma import.',
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
    final minUses = int.tryParse(argResults!.option('min-component-uses')!);
    if (minUses == null || minUses < 1) {
      usageException('--min-component-uses must be a positive integer');
    }
    RuntimeScreens? rendered;
    if (argResults!.flag('runtime')) {
      stdout.writeln('Rendering screens with Flutter...');
      rendered = await renderScreens(
        analysis,
        flutterCommand: argResults!.option('flutter')?.split(' '),
        width: double.parse(size.group(1)!).round(),
        height: double.parse(size.group(2)!).round(),
        screenshotsDir: argResults!.option('screenshots'),
      );
    }
    final compiled =
        FlutterCompiler(
          designSystem: argResults!.flag('design-system'),
          minComponentUses: minUses,
          brightness: switch (argResults!.option('brightness')) {
            'light' => ThemeBrightness.light,
            'dark' => ThemeBrightness.dark,
            _ => null,
          },
          screenWidth: double.parse(size.group(1)!),
          screenHeight: double.parse(size.group(2)!),
          iconFonts: projectIconFonts(analysis.root),
        ).compile(
          analysis,
          rendered: rendered?.screens ?? const {},
          renderedImages: rendered?.images ?? const {},
        );
    final ir = IrDocument(
      project: compiled.project,
      screens: compiled.screens,
      designSystem: compiled.designSystem,
      images: compiled.images,
      diagnostics: [...?rendered?.diagnostics, ...compiled.diagnostics],
    );

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
      ..writeln('  $nodes nodes');
    if (ir.designSystem case final ds?) {
      final variants = ds.components.fold(0, (n, c) => n + c.variants.length);
      stdout
        ..writeln(
          '  ${ds.colors.length} color variables (${ds.modes.join(' / ')})',
        )
        ..writeln('  ${ds.textStyles.length} text styles')
        ..writeln('  ${ds.shadows.length} effect styles')
        ..writeln('  ${ds.components.length} components ($variants variants)');
    }
    stdout
      ..writeln()
      ..writeln(
        '  ${p.relative(designFile.path)}   ← import with the Figma plugin',
      )
      ..writeln('  ${p.relative(irFile.path)}');
    return 0;
  }
}

class ThemeCommand extends _ProjectCommand {
  ThemeCommand() {
    argParser.addOption(
      'brightness',
      allowed: ['light', 'dark'],
      defaultsTo: 'light',
      help: 'Which app theme to resolve.',
    );
  }

  @override
  String get name => 'theme';

  @override
  String get description =>
      'Print the app theme as resolved statically (Theme.of(context) as JSON).';

  @override
  String get invocation => '${runner!.executableName} theme [project]';

  @override
  Future<int> run() async {
    final analysis = await FlutterProjectAnalyzer(projectPath).analyze();
    final extractor = ThemeExtractor(ValueEvaluator(const MaterialTheme()));
    final theme = extractor.fromProject(
      analysis,
      brightness: argResults!.option('brightness') == 'dark'
          ? ThemeBrightness.dark
          : ThemeBrightness.light,
    );
    for (final d in extractor.diagnostics) {
      stderr.writeln('${d.severity.name}: ${d.message}');
    }
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(describeTheme(theme)),
    );
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
