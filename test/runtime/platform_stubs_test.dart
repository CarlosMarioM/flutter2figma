import 'dart:io';

import 'package:flutter2figma/src/runtime/platform_stubs.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('f2f_stubs'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('Pigeon host methods are answered with an empty value of their type', () {
    final lib = Directory(p.join(dir.path, 'plugin', 'lib'))
      ..createSync(recursive: true);
    File(p.join(lib.path, 'messages.g.dart')).writeAsStringSync(r"""
class HostApi {
  Future<bool> fetchAndActivate(String appName) async {
    final String pigeonVar_channelName =
        'dev.flutter.pigeon.plugin.HostApi.fetchAndActivate$pigeonVar_messageChannelSuffix';
  }
  Future<Map<String, Object?>> getAll(String appName) async {
    final String pigeonVar_channelName = 'dev.flutter.pigeon.plugin.HostApi.getAll';
  }
  Future<Settings> settings() async {
    final String pigeonVar_channelName = 'dev.flutter.pigeon.plugin.HostApi.settings';
  }
}
""");
    final stubs = pigeonStubs({'plugin': p.join(dir.path, 'plugin')});
    expect(stubs, [
      "  _stubPigeon('dev.flutter.pigeon.plugin.HostApi.fetchAndActivate', false);",
      "  _stubPigeon('dev.flutter.pigeon.plugin.HostApi.getAll', <Object?, Object?>{});",
    ]);
  });

  test('a missing .env asset gets the keys the app reads', () {
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: app
flutter:
  assets:
    - assets/images/
    - .env
''');
    Directory(p.join(dir.path, 'lib')).createSync();
    File(p.join(dir.path, 'lib', 'main.dart')).writeAsStringSync('''
final url = dotenv.env['SUPABASE_URL']!;
final key = dotenv.get('ANON_KEY');
''');
    final missing = missingAssets(dir.path);
    expect(missing.keys, [p.join(dir.path, '.env')]);
    expect(
      missing.values.single,
      contains('SUPABASE_URL=http://127.0.0.1:9\nANON_KEY=placeholder'),
    );
  });
}
