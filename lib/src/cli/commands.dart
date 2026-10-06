import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:flutter2figma/analyzer.dart';
import 'package:flutter2figma/compiler.dart';
import 'package:flutter2figma/figma.dart';
import 'package:flutter2figma/ir.dart';
import 'package:path/path.dart' as p;

import '../preview/preview.dart';
import '../runtime/runtime_export.dart';
import '../version.dart';

/// Where people get the Figma plugin.
const pluginUrl = 'https://www.figma.com/community/plugin/1687559887675755742';

CommandRunner<int> buildRunner() => _Runner()
  ..addCommand(AnalyzeCommand())
  ..addCommand(ExportCommand())
  ..addCommand(ThemeCommand());

class _Runner extends CommandRunner<int> {
  _Runner()
    : super(
        'flutter2figma',
        'Convert Flutter UIs into editable Figma designs.\n\n'
            'Run it with no command in a Flutter app to export it.',
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

  /// Plain `flutter2figma` in a Flutter app exports it, export options
  /// included (`flutter2figma --static`).
  @override
  Future<int?> run(Iterable<String> args) {
    final list = args.toList();
    final first = list.firstOrNull;
    final exports =
        (first == null ||
            (first.startsWith('-') &&
                !const {'-h', '--help', '--version'}.contains(first))) &&
        _isFlutterApp(Directory.current.path);
    return super.run(exports ? ['export', ...list] : list);
  }

  static bool _isFlutterApp(String dir) {
    final pubspec = File(p.join(dir, 'pubspec.yaml'));
    return pubspec.existsSync() &&
        RegExp(
          r'^\s+flutter:\s*\n\s+sdk:\s*flutter',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync());
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
            'Run the app in a Flutter test (flutter test) and export exactly '
            'what each screen draws. Screens that can\'t run are exported '
            'from the code alone. This runs the app\'s main().',
        defaultsTo: true,
      )
      ..addFlag(
        'static',
        negatable: false,
        help:
            'Only read the code; don\'t run the app (same as --no-runtime). '
            'Needs no Flutter, but what the app decides at runtime shows as '
            'placeholders.',
      )
      ..addOption(
        'flutter',
        help:
            'Flutter command for --runtime, e.g. "fvm flutter". Detected '
            'when omitted (FVM if the project pins a version).',
      )
      ..addFlag(
        'auto-layout',
        help:
            'Turn rows and columns Flutter rendered into Figma auto layout '
            'where it keeps Flutter\'s positions. Off: everything absolute.',
        defaultsTo: true,
      )
      ..addOption(
        'screenshots',
        help:
            'Also save Flutter\'s own render of each screen as PNG in this '
            'directory, to compare with the Figma import.',
      )
      ..addFlag(
        'preview',
        help:
            'Write preview.html: every screen drawn from design.json in the '
            'browser, beside Flutter\'s own render.',
        defaultsTo: true,
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
    final runtime = argResults!.flag('runtime') && !argResults!.flag('static');
    final preview = argResults!.flag('preview');
    // The preview shows Flutter's renders beside the export.
    var shots = argResults!.option('screenshots');
    Directory? tempShots;
    if (preview && shots == null && runtime) {
      tempShots = Directory.systemTemp.createTempSync('flutter2figma_shots');
      shots = tempShots.path;
    }
    if (runtime) {
      stdout.writeln(
        'Running the app in a Flutter test to record each screen '
        '(--static to only read the code)...',
      );
      rendered = await renderScreens(
        analysis,
        flutterCommand: argResults!.option('flutter')?.split(' '),
        autoLayout: argResults!.flag('auto-layout'),
        width: double.parse(size.group(1)!).round(),
        height: double.parse(size.group(2)!).round(),
        screenshotsDir: shots,
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
    File(
      p.join(out.path, 'ir.json'),
    ).writeAsStringSync(encoder.convert(ir.toJson()));
    final designFile = File(p.join(out.path, 'design.json'))
      ..writeAsStringSync(encoder.convert(design));
    File? previewFile;
    if (preview) {
      final screenshots = <String, List<int>>{};
      final dir = shots == null ? null : Directory(shots);
      if (dir != null && dir.existsSync()) {
        for (final f in dir.listSync().whereType<File>()) {
          if (!f.path.endsWith('.png')) continue;
          screenshots[p.basenameWithoutExtension(f.path)] = halfSize(
            f.readAsBytesSync(),
          );
        }
      }
      tempShots?.deleteSync(recursive: true);
      previewFile = File(p.join(out.path, 'preview.html'))
        ..writeAsStringSync(
          previewPage(
            design: design,
            title: analysis.name,
            screenshots: screenshots,
            fonts: usedFonts(design, projectFontFiles(analysis.root)),
          ),
        );
    }

    var nodes = 0;
    void count(IrNode n) {
      nodes++;
      if (n is IrFrame) n.children.forEach(count);
    }

    for (final s in ir.screens) {
      count(s.root);
    }

    // What the summary below says is left out of the diagnostics.
    printDiagnostics([
      for (final d in (design['diagnostics'] as List))
        if (!(d as Map)['message'].toString().startsWith('Runtime'))
          IrDiagnostic.fromJson(d.cast<String, Object?>()),
    ], verbose: argResults!.flag('verbose'));
    stdout
      ..writeln()
      ..writeln('✓ Exported ${ir.screens.length} screens, $nodes layers');
    if (ir.designSystem case final ds?) {
      final variants = ds.components.fold(0, (n, c) => n + c.variants.length);
      stdout.writeln(
        '  ${ds.colors.length} color variables (${ds.modes.join(' / ')}), '
        '${ds.textStyles.length} text styles, ${ds.shadows.length} effect '
        'styles, ${ds.components.length} components ($variants variants)',
      );
    }
    _summary(ir.screens.length, rendered);
    final open = Platform.isMacOS
        ? 'open'
        : Platform.isWindows
        ? 'start'
        : 'xdg-open';
    stdout
      ..writeln()
      ..writeln('Next:');
    // Inside the project: short paths. Elsewhere: paths that work from
    // anywhere.
    String shown(String path) => p.isWithin(Directory.current.path, path)
        ? p.relative(path)
        : p.normalize(p.absolute(path));
    if (previewFile != null) {
      stdout.writeln(
        '  Check:   $open ${shown(previewFile.path)}   '
        '(${rendered == null || rendered.screens.isEmpty ? 'each screen' : 'each screen beside the app'}, '
        'in the browser)',
      );
    }
    stdout
      ..writeln(
        '  Import:  in Figma, Plugins → Flutter2Figma, then drop '
        '${shown(designFile.path)}',
      )
      ..writeln('           Get the plugin: $pluginUrl');
    return 0;
  }

  /// How exact the export is: which screens Flutter rendered, which come
  /// from the code alone and why, and what would fix them.
  void _summary(int total, RuntimeScreens? rendered) {
    stdout.writeln();
    if (rendered == null) {
      stdout
        ..writeln('! Exported from the code alone (--static): what the app')
        ..writeln('  decides at runtime (state, translations, data, custom')
        ..writeln('  painting) shows as placeholders. Leave out --static to')
        ..writeln('  run the app and export exactly what each screen draws.');
      return;
    }
    final fallbacks = rendered.fallbacks;
    if (fallbacks.isEmpty) {
      stdout.writeln('  All $total screens rendered by Flutter.');
      return;
    }
    stdout.writeln(
      '  ${total - fallbacks.length} of $total screens rendered by Flutter.',
    );
    // One reason for every screen: the app itself didn't start.
    final reasons = fallbacks.values.toSet();
    if (fallbacks.length == total && reasons.length == 1) {
      stdout
        ..writeln('! All screens exported from the code alone, so they may')
        ..writeln('  show placeholders. The app didn\'t start in a test:')
        ..writeln('    ${reasons.single}');
      // The app's own startup failed (not a missing Flutter): setUp() in
      // the setup file is where that gets fixed.
      final startup = RegExp(r'^(main\(\)|setUp|The app has no|flutter test)');
      if (startup.hasMatch(reasons.single)) {
        stdout
          ..writeln('  test/flutter2figma_setup.dart can set things up before')
          ..writeln('  main() runs: see "Runtime mode" in the README.');
      }
      return;
    }
    stdout.writeln('! Exported from the code alone (may show placeholders):');
    for (final MapEntry(key: name, value: reason) in fallbacks.entries) {
      stdout.writeln('    $name: $reason');
    }
    if (reasons.contains('it needs constructor arguments')) {
      stdout
        ..writeln('  Build screens that need arguments in')
        ..writeln('  test/flutter2figma_setup.dart (buildScreen): see')
        ..writeln('  "Runtime mode" in the README.');
    }
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
