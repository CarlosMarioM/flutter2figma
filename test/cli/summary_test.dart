import 'package:flutter2figma/src/cli/commands.dart';
import 'package:flutter2figma/src/runtime/runtime_export.dart';
import 'package:test/test.dart';

String summary(int total, RuntimeScreens? rendered) {
  final out = StringBuffer();
  writeExportSummary(out, total, rendered);
  return out.toString();
}

RuntimeScreens runtime(Map<String, String> fallbacks) =>
    RuntimeScreens({}, {}, [], fallbacks: fallbacks);

void main() {
  test('static export says so', () {
    expect(summary(3, null), contains('--static'));
  });

  test('all rendered', () {
    expect(summary(3, runtime({})), contains('All 3 screens rendered'));
  });

  test('11 of 12: reason and fix for the one that fell back', () {
    final out = summary(
      12,
      runtime({'AiInsightsScreen': 'it needs constructor arguments'}),
    );
    expect(out, contains('11 of 12 screens rendered by Flutter.'));
    expect(out, contains('Needs constructor arguments (1)'));
    expect(out, contains('AiInsightsScreen'));
    expect(out, contains('Fix: Build it in buildScreen'));
  });

  test('groups screens by category, one fix per group', () {
    final out = summary(
      5,
      runtime({
        'A': 'it needs constructor arguments',
        'B': 'MissingPluginException(No implementation found)',
        'C': 'it needs constructor arguments',
        'D': 'RangeError (index): Invalid value\nmore',
      }),
    );
    expect(out, contains('1 of 5 screens rendered by Flutter.'));
    expect(out, contains('Needs constructor arguments (2)'));
    expect(out, contains('Plugin or platform channel (1)'));
    expect(out, contains('Unknown error (1)'));
    expect(out, contains('D: RangeError (index): Invalid value'));
    expect(out, isNot(contains('more')));
    expect('Fix:'.allMatches(out), hasLength(3));
  });

  test('all screens with the same reason: the app didn\'t start', () {
    final out = summary(
      2,
      runtime({'A': 'main() threw: boom', 'B': 'main() threw: boom'}),
    );
    expect(out, contains('All screens exported from the code alone'));
    expect(out, contains('main() threw: boom'));
    expect(out, contains('Fix: Set things up'));
  });
}
