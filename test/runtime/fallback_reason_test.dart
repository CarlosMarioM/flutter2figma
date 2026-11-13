import 'package:flutter2figma/src/runtime/runtime_export.dart';
import 'package:test/test.dart';

void main() {
  const cases = <(String, String, String)>[
    (
      'it needs constructor arguments',
      'Needs constructor arguments',
      'buildScreen',
    ),
    (
      'main() threw: StateError: boom',
      'The app didn\'t start in a test',
      'setUp',
    ),
    ('setUp failed: bad', 'The app didn\'t start in a test', 'setUp'),
    (
      'Navigator operation requested with a context that does not include a Navigator.',
      'Missing Navigator',
      'wrapScreen',
    ),
    (
      'MissingPluginException(No implementation found for method getAll)',
      'Plugin or platform channel',
      'setMockMethodCallHandler',
    ),
    (
      'Error: Could not find the correct Provider<Cart> above this widget',
      'Provider or bloc not found',
      'wrapScreen',
    ),
    (
      'TimeoutException after 0:00:30: pumpAndSettle timed out',
      'Timed out',
      'setUp',
    ),
  ];

  for (final (reason, category, hintPart) in cases) {
    test('explains "$reason"', () {
      final e = explainFallback(reason);
      expect(e.category, category);
      expect(e.hint, contains(hintPart));
    });
  }

  test('unknown errors keep the raw first line, truncated', () {
    final e = explainFallback('RangeError (index): Invalid value\nstack...');
    expect(e.category, unknownFallbackCategory);
    expect(e.cause, 'RangeError (index): Invalid value');
    final long = explainFallback('X' * 300);
    expect(long.cause.length, 120);
    expect(long.cause, endsWith('...'));
  });

  test('"Flutter didn\'t render it" is unknown', () {
    expect(
      explainFallback('Flutter didn\'t render it').category,
      unknownFallbackCategory,
    );
  });
}
