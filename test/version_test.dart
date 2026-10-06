import 'dart:convert';
import 'dart:io';

import 'package:flutter2figma/figma.dart';
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

    // The Figma plugin ships with the same version; it compares it with the
    // version that wrote a design.json to ask for an update.
    final plugin =
        jsonDecode(File('figma-plugin/package.json').readAsStringSync())
            as Map<String, Object?>;
    expect(plugin['version'], version, reason: 'figma-plugin/package.json');
    expect(
      File('figma-plugin/src/version.ts').readAsStringSync(),
      contains("export const PLUGIN_VERSION = '$version';"),
      reason: 'figma-plugin/src/version.ts',
    );
    // The exporter and the plugin agree on the file format version.
    expect(
      File('figma-plugin/src/design.ts').readAsStringSync(),
      contains('export const DESIGN_VERSION = $designVersion;'),
      reason: 'figma-plugin/src/design.ts',
    );

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
