import 'dart:io';

import 'package:flutter2figma/flutter2figma.dart';
import 'package:test/test.dart';

void main() {
  test('packageVersion matches pubspec.yaml and CHANGELOG.md', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(packageVersion, version);

    final changelog = File('CHANGELOG.md').readAsStringSync();
    expect(
      changelog,
      startsWith('## $version'),
      reason: 'CHANGELOG.md must start with the current version',
    );
  });
}
