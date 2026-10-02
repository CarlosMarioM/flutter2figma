import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../analyzer/project_analyzer.dart';
import 'harness.dart';

/// One screen as Flutter rendered it: a tree of recorded nodes (see
/// `harness.dart`), the theme it rendered with, and its images (PNG).
class CapturedScreen {
  CapturedScreen({
    required this.name,
    required this.width,
    required this.height,
    required this.tree,
    required this.theme,
    required this.images,
  });

  factory CapturedScreen.fromJson(Map<String, Object?> json) => CapturedScreen(
    name: json['name'] as String,
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
    tree: (json['tree'] as List).cast<Map<String, Object?>>(),
    theme: (json['theme'] as Map?)?.cast<String, Object?>() ?? const {},
    images: {
      for (final MapEntry(:key, :value)
          in ((json['images'] as Map?) ?? const {}).entries)
        key as String: base64Decode(value as String),
    },
  );

  final String name;
  final double width, height;
  final List<Map<String, Object?>> tree;
  final Map<String, Object?> theme;
  final Map<String, List<int>> images;
}

class CaptureResult {
  CaptureResult({
    required this.screens,
    required this.errors,
    required this.skipped,
    this.log = '',
  });

  final List<CapturedScreen> screens;

  /// Why the app or a screen couldn't be captured.
  final List<String> errors;

  /// Screens that can't be built without arguments.
  final List<String> skipped;

  /// `flutter test` output, for troubleshooting.
  final String log;
}

/// Renders a project's screens with Flutter (`flutter test`) and records
/// them. The app runs for real, so it must start in a test environment:
/// platform plugins that are missing in tests are tolerated, but a `main()`
/// that blocks on them, or screens that need route arguments, fall back to
/// static export.
///
/// Writes one generated file, `.dart_tool/flutter2figma/capture_test.dart`,
/// inside the project and deletes it afterwards. Nothing else in the
/// project changes (besides what `flutter test` itself caches).
class RuntimeCapture {
  RuntimeCapture(
    this.projectRoot, {
    this.flutterCommand,
    this.width = 390,
    this.height = 844,
    this.timeout = const Duration(minutes: 10),
  });

  /// The whole `flutter test` run is stopped after this.
  final Duration timeout;

  final String projectRoot;

  /// e.g. `['fvm', 'flutter']`; detected when null.
  final List<String>? flutterCommand;
  final int width, height;

  Future<CaptureResult> run(ProjectAnalysis analysis) async {
    final root = p.normalize(p.absolute(projectRoot));
    if (!File(p.join(root, 'lib', 'main.dart')).existsSync()) {
      return CaptureResult(
        screens: const [],
        errors: const ['No lib/main.dart to start the app from'],
        skipped: const [],
      );
    }
    final buildable = [
      for (final s in analysis.screens)
        if (s.placeholderArguments != null && s.library != null) s,
    ];
    final skipped = [
      for (final s in analysis.screens)
        if (!buildable.contains(s)) s.name,
    ];
    // A screen that gets its blocs or providers from a wrapper class
    // (`MenuScreen` providing them to `MenuPage`) is built through the
    // outermost such wrapper.
    WidgetClass entry(WidgetClass screen) {
      var best = screen;
      for (final w in analysis.widgets) {
        final path = w.scaffoldPath;
        if (path == null ||
            !path.contains(screen.name) ||
            !w.buildableWithoutArguments ||
            w.library == null) {
          continue;
        }
        if (best == screen || path.length > best.scaffoldPath!.length) best = w;
      }
      return best;
    }

    final screens = {for (final s in buildable) s.name: s};
    final entries = {for (final s in buildable) s.name: entry(s)};
    final prefixes = <String, String>{};
    for (final w in entries.values) {
      prefixes.putIfAbsent(w.library!, () => 's${prefixes.length}');
    }
    final setup = _setup(root);
    final source = harnessSource(
      mainImport: 'package:${analysis.name}/main.dart',
      screenImports: prefixes,
      screens: {
        for (final MapEntry(key: name, value: w) in entries.entries)
          name:
              '${prefixes[w.library]}.${w.name}(${w == screens[name] ? w.placeholderArguments : ''})',
      },
      setupImports: setup.imports,
      setup: setup.code,
      wrap: setup.wrap,
      build: setup.build,
      nested: packageRoots(root).containsKey('nested'),
    );

    final dir = Directory(p.join(root, '.dart_tool', 'flutter2figma'))
      ..createSync(recursive: true);
    final harness = File(p.join(dir.path, 'capture_test.dart'))
      ..writeAsStringSync(source);
    final temp = Directory.systemTemp.createTempSync('flutter2figma_capture');
    final out = File(p.join(temp.path, 'capture.json'));
    try {
      final command = flutterCommand ?? detectFlutter(root);
      final flutterRoot = flutterSdkRoot(root);
      final process = await Process.start(
        command.first,
        [
          ...command.skip(1),
          'test',
          p.relative(harness.path, from: root),
          '--dart-define=F2F_OUT=${out.path}',
          if (flutterRoot != null)
            '--dart-define=F2F_FLUTTER_ROOT=$flutterRoot',
          '--dart-define=F2F_WIDTH=$width',
          '--dart-define=F2F_HEIGHT=$height',
        ],
        workingDirectory: root,
        runInShell: Platform.isWindows,
      );
      final stdoutText = process.stdout.transform(utf8.decoder).join();
      final stderrText = process.stderr.transform(utf8.decoder).join();
      var timedOut = false;
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
          process.kill();
          return -1;
        },
      );
      final processLog = (
        exitCode: exitCode,
        stdout: await stdoutText,
        stderr: await stderrText,
      );
      final log = '${processLog.stdout}\n${processLog.stderr}';
      if (timedOut) {
        return CaptureResult(
          screens: const [],
          errors: [
            'flutter test did not finish within ${timeout.inMinutes} minutes',
          ],
          skipped: skipped,
          log: log,
        );
      }
      if (!out.existsSync()) {
        return CaptureResult(
          screens: const [],
          errors: ['flutter test failed before capturing: ${_firstError(log)}'],
          skipped: skipped,
          log: log,
        );
      }
      final json = jsonDecode(out.readAsStringSync()) as Map<String, Object?>;
      return CaptureResult(
        screens: [
          for (final s
              in (json['screens'] as List).cast<Map<String, Object?>>())
            CapturedScreen.fromJson(s),
        ],
        errors: [
          ...(json['errors'] as List).cast<String>(),
          if (processLog.exitCode != 0 && (json['screens'] as List).isEmpty)
            'flutter test: ${_firstError(log)}',
        ],
        skipped: skipped,
        log: log,
      );
    } finally {
      if (harness.existsSync()) harness.deleteSync();
      temp.deleteSync(recursive: true);
    }
  }

  /// Fakes for common plugins the app depends on (they have no platform
  /// side in tests), and the app's own `test/flutter2figma_setup.dart`:
  ///
  /// ```dart
  /// Future<void> setUp() async { /* mocks, dependency injection */ }
  /// Widget wrapScreen(String name, Widget screen) => /* providers */;
  /// Widget? buildScreen(String name) => /* screens needing real arguments */;
  /// ```
  static ({List<String> imports, List<String> code, String wrap, String build})
  _setup(String root) {
    final packages = packageRoots(root);
    final imports = <String>[];
    final code = <String>[];
    for (final (i, fake) in _fakes.indexed) {
      final dir = packages[fake.package];
      if (dir == null || !File(p.join(dir, fake.file)).existsSync()) continue;
      imports.addAll([
        for (final (j, uri) in fake.imports.indexed)
          "import '$uri' as fk${i}_$j;",
      ]);
      code.add('  try { ${fake.code(i)} } catch (_) {}');
    }
    var wrap = 'screen';
    var build = 'fallback()';
    final user = File(p.join(root, 'test', 'flutter2figma_setup.dart'));
    if (user.existsSync()) {
      final text = user.readAsStringSync();
      imports.add("import '../../test/flutter2figma_setup.dart' as user;");
      if (RegExp(r'^\S.*\bsetUp\s*\(', multiLine: true).hasMatch(text)) {
        code.add('  await user.setUp();');
      }
      if (RegExp(r'\bwrapScreen\s*\(').hasMatch(text)) {
        wrap = 'user.wrapScreen(name, screen)';
      }
      if (RegExp(r'\bbuildScreen\s*\(').hasMatch(text)) {
        build = 'user.buildScreen(name) ?? fallback()';
      }
    }
    return (imports: imports, code: code, wrap: wrap, build: build);
  }

  static String _firstError(String log) {
    final line = log
        .split('\n')
        .map((l) => l.trim())
        .firstWhere(
          (l) =>
              l.contains('Exception') ||
              l.contains('Error') ||
              l.contains('error:'),
          orElse: () => log.trim().split('\n').last,
        );
    return line.length > 300 ? '${line.substring(0, 300)}…' : line;
  }
}

/// A plugin's in-memory replacement for tests, set up when the app depends
/// on [package] and its resolved version has [file].
class _Fake {
  const _Fake(this.package, this.file, this.imports, this.code);

  final String package;
  final String file;
  final List<String> imports;

  /// The statement, given the fake's index (imports are `fk<i>_<j>`).
  final String Function(int i) code;
}

final _fakes = [
  _Fake(
    'shared_preferences',
    'lib/shared_preferences.dart',
    ['package:shared_preferences/shared_preferences.dart'],
    (i) => 'fk${i}_0.SharedPreferences.setMockInitialValues({});',
  ),
  _Fake(
    'shared_preferences_platform_interface',
    'lib/in_memory_shared_preferences_async.dart',
    [
      'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart',
      'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart',
    ],
    (i) =>
        'fk${i}_1.SharedPreferencesAsyncPlatform.instance = '
        'fk${i}_0.InMemorySharedPreferencesAsync.empty();',
  ),
  _Fake(
    'flutter_secure_storage',
    'lib/flutter_secure_storage.dart',
    ['package:flutter_secure_storage/flutter_secure_storage.dart'],
    (i) => 'fk${i}_0.FlutterSecureStorage.setMockInitialValues({});',
  ),
];

/// Package name → root directory, from `.dart_tool/package_config.json`.
Map<String, String> packageRoots(String projectRoot) {
  final config = File(p.join(projectRoot, '.dart_tool', 'package_config.json'));
  if (!config.existsSync()) return {};
  try {
    final json = jsonDecode(config.readAsStringSync()) as Map;
    return {
      for (final pkg in (json['packages'] as List).cast<Map>())
        pkg['name'] as String: p.normalize(
          config.parent.uri.resolve(pkg['rootUri'] as String).toFilePath(),
        ),
    };
  } on FormatException {
    return {};
  }
}

/// The project's Flutter command: the SDK its packages were resolved with
/// (what `flutter pub get` used, FVM or not), else `flutter` from PATH, else
/// FVM.
List<String> detectFlutter(String projectRoot) {
  final sdk = flutterSdkRoot(projectRoot);
  if (sdk != null) {
    final flutter = File(
      p.join(sdk, 'bin', Platform.isWindows ? 'flutter.bat' : 'flutter'),
    );
    if (flutter.existsSync()) return [flutter.path];
  }
  final which = Process.runSync(Platform.isWindows ? 'where' : 'which', [
    'flutter',
  ]);
  if (which.exitCode == 0) return ['flutter'];
  return ['fvm', 'flutter'];
}

/// The Flutter SDK the project resolves against (`.dart_tool/package_config`).
String? flutterSdkRoot(String projectRoot) {
  final flutter = packageRoots(projectRoot)['flutter'];
  return flutter == null ? null : p.normalize(p.join(flutter, '..', '..'));
}
