@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'plain flutter2figma in a Flutter app exports it, with next steps',
    () async {
      final out = Directory.systemTemp.createTempSync('f2f_bare');
      addTearDown(() => out.deleteSync(recursive: true));
      // Run inside the app, as people do: a child process, since the
      // working directory is shared by every test in this one.
      final result = await Process.run(Platform.resolvedExecutable, [
        '--packages=${p.absolute('.dart_tool', 'package_config.json')}',
        p.absolute('bin', 'flutter2figma.dart'),
        '--static',
        '-o',
        out.path,
      ], workingDirectory: 'example');

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final printed = result.stdout as String;
      expect(printed, contains('Exported from the code alone (--static)'));
      expect(printed, contains('Next:'));
      expect(printed, contains('preview.html'));
      expect(File(p.join(out.path, 'preview.html')).existsSync(), isTrue);
      final design =
          jsonDecode(File(p.join(out.path, 'design.json')).readAsStringSync())
              as Map;
      expect(design['screens'], isNotEmpty);
    },
  );
}
