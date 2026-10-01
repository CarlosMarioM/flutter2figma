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

    var changelog = File('CHANGELOG.md').readAsStringSync();
    // Work in progress is listed under "## Unreleased" until it's released;
    // a release (a tag build) must have named it.
    final releasing =
        Platform.environment['GITHUB_REF']?.startsWith('refs/tags/') ?? false;
    if (!releasing && changelog.startsWith('## Unreleased')) {
      changelog = changelog.substring(changelog.indexOf('\n## ') + 1);
    }
    expect(
      changelog,
      startsWith('## $version'),
      reason: 'CHANGELOG.md must start with the current version',
    );
  });
}
