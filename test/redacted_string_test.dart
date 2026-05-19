import 'package:flutter_test/flutter_test.dart';
import 'package:prelude_flutter_auth_sdk/prelude_flutter_auth_sdk.dart';

/// Anchors [RedactedString]'s "do not appear in logs" contract.
/// Anything that lets the underlying secret leak via interpolation,
/// `toString`, error messages, or collection debug output is a
/// behavioural regression.
void main() {
  group('RedactedString', () {
    test('toString hides the value', () {
      const r = RedactedString('hunter2');
      expect(r.toString(), '<redacted>');
      expect(r.toString(), isNot(contains('hunter2')));
    });

    test('string interpolation hides the value', () {
      const r = RedactedString('hunter2');
      // The most common accidental log path: \$r in a print call.
      expect('value=$r', 'value=<redacted>');
    });

    test('value is reachable explicitly', () {
      const r = RedactedString('hunter2');
      expect(r.value, 'hunter2');
    });

    test('equality + hashCode use the underlying value', () {
      expect(const RedactedString('a') == const RedactedString('a'), isTrue);
      expect(const RedactedString('a') == const RedactedString('b'), isFalse);
      expect(
        const RedactedString('a').hashCode,
        const RedactedString('a').hashCode,
      );
    });
  });
}
