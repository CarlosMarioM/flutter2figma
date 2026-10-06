import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Answers for the app's plugins, which have no platform side in a test.
///
/// Pigeon host APIs (`dev.flutter.pigeon.…` channels) are found in every
/// package the app depends on, and each call is answered with an empty value
/// of its return type (`false`, `0`, `''`, `[]`, `{}`, `null`), so a `main()`
/// that awaits a plugin (Firebase Remote Config's `fetchAndActivate`, ...)
/// keeps going instead of throwing. Methods returning a Pigeon class aren't
/// answered: there is no empty value to give.
///
/// Returns Dart statements for the harness's setup.
List<String> pigeonStubs(Map<String, String> packages) {
  final channels = <String, String>{};
  for (final MapEntry(key: name, value: dir) in packages.entries) {
    if (name == 'flutter' || name == 'flutter_test') continue;
    final lib = Directory(p.join(dir, 'lib'));
    if (!lib.existsSync()) continue;
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final String text;
      try {
        text = file.readAsStringSync();
      } on FileSystemException {
        continue;
      }
      if (!text.contains("'dev.flutter.pigeon.")) continue;
      for (final m in _hostMethod.allMatches(text)) {
        final value = _empty(m.group(1)!);
        if (value != null) channels.putIfAbsent(m.group(2)!, () => value);
      }
    }
  }
  return [
    for (final MapEntry(key: channel, value: value) in channels.entries)
      "  _stubPigeon('$channel', $value);",
  ];
}

/// A host API method: its return type, then (first string in its body) the
/// channel it sends on, without the `$suffix` some generators append.
final _hostMethod = RegExp(
  r"Future<([\w<>?, ]+)>\s+\w+\([^)]*\)\s*async\s*\{[^']*'(dev\.flutter\.pigeon\.[\w.]+)",
);

/// The empty value of a Pigeon return type, as Dart source.
String? _empty(String type) {
  type = type.trim();
  if (type.endsWith('?') || type == 'void' || type == 'Object') return 'null';
  if (type == 'bool') return 'false';
  if (type == 'int') return '0';
  if (type == 'double') return '0.0';
  if (type == 'String') return "''";
  if (type.startsWith('List<')) return '<Object?>[]';
  if (type.startsWith('Map<')) return '<Object?, Object?>{}';
  return null;
}

/// Asset files the pubspec lists that don't exist (a gitignored `.env`):
/// `flutter test` refuses to build without them. The caller creates them
/// for the run with these contents and deletes them afterwards.
///
/// A dotenv file gets every key the app reads from it, with placeholder
/// values, so `dotenv.env['API_URL']!` doesn't throw.
Map<String, String> missingAssets(String root) {
  final pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return const {};
  final List<String> assets;
  try {
    final yaml = loadYaml(pubspec.readAsStringSync());
    final flutter = yaml is YamlMap ? yaml['flutter'] : null;
    final list = flutter is YamlMap ? flutter['assets'] : null;
    assets = [
      for (final a in list is YamlList ? list : const [])
        if (a is String)
          a
        else if (a is YamlMap && a['path'] is String)
          a['path'] as String,
    ];
  } on Exception {
    return const {};
  }
  final missing = <String, String>{};
  for (final asset in assets) {
    if (asset.endsWith('/')) continue;
    final path = p.join(root, asset);
    if (File(path).existsSync() || Directory(path).existsSync()) continue;
    missing[path] = p.basename(asset).contains('.env') ? _dotenv(root) : '';
  }
  return missing;
}

String _dotenv(String root) {
  final keys = <String>{};
  final lib = Directory(p.join(root, 'lib'));
  if (lib.existsSync()) {
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final text = file.readAsStringSync();
      if (!text.contains('dotenv')) continue;
      for (final m in _envKey.allMatches(text)) {
        keys.add(m.group(1) ?? m.group(2)!);
      }
    }
  }
  return [
    '# Placeholder written by flutter2figma for a runtime capture.',
    for (final key in keys)
      // URLs must parse; nothing listens on this port, so calls fail fast.
      '$key=${RegExp('URL|URI|HOST|ENDPOINT').hasMatch(key) ? 'http://127.0.0.1:9' : 'placeholder'}',
  ].join('\n');
}

/// `env['KEY']`, `dotenv.get('KEY')`, `maybeGet`, `getInt`, ...
final _envKey = RegExp(
  r"""env\[\s*['"]([A-Za-z_][\w]*)['"]\s*\]|\.(?:get|maybeGet|getInt|getDouble|getBool)\(\s*['"]([A-Za-z_][\w]*)['"]""",
);
