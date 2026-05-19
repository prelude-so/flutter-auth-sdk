import 'package:flutter_test/flutter_test.dart';
import 'package:prelude_flutter_auth_sdk/prelude_flutter_auth_sdk.dart';

/// Coverage for the Dart password classifier: Unicode-category
/// partitioning across ASCII, non-ASCII, and astral-plane
/// characters. Length is counted in code points (so emoji and
/// astral-plane characters count as one), and anything that is
/// not in the Lu / Ll / Nd general-category groups is treated
/// as a symbol.
void main() {
  // Common compliancy used by most cases. minLength=8 keeps the
  // assertions short; per-test cases override as needed.
  const standard = PreludePasswordCompliancy(
    minLength: 8,
    maxLength: 64,
    uppercase: 1,
    lowercase: 1,
    numbers: 1,
    symbols: 1,
  );

  PreludePasswordCompliancyResult resultFor(
    PreludePasswordCompliancyResults results,
    PreludePasswordCompliancyCriterion criterion,
  ) =>
      results.results.firstWhere((r) => r.criterion == criterion);

  group('validate', () {
    test('all rules pass on a typical mixed password', () {
      final out = PreludeAuthClient.validate(
        password: 'Abcd1234!',
        against: standard,
      );
      expect(out.valid, isTrue);
      expect(out.results.every((r) => r.valid), isTrue);
    });

    test('flags missing classes individually', () {
      final out = PreludeAuthClient.validate(
        password: 'abcdefgh', // 8 lowercase, nothing else
        against: standard,
      );
      expect(out.valid, isFalse);
      expect(
        resultFor(out, PreludePasswordCompliancyCriterion.lowercase).valid,
        isTrue,
      );
      expect(
        resultFor(out, PreludePasswordCompliancyCriterion.uppercase).valid,
        isFalse,
      );
      expect(
        resultFor(out, PreludePasswordCompliancyCriterion.numbers).valid,
        isFalse,
      );
      expect(
        resultFor(out, PreludePasswordCompliancyCriterion.symbols).valid,
        isFalse,
      );
    });

    test('counts in Unicode code points, not UTF-16 units', () {
      // 🔒 is one code point but two UTF-16 units. iOS counts in
      // scalars; the Dart implementation must match.
      final out = PreludeAuthClient.validate(
        password: 'Aa1🔒',
        against: standard,
      );
      final length = resultFor(out, PreludePasswordCompliancyCriterion.minLength);
      expect(length.actual, 4);
    });

    test('non-ASCII letter cases (Latin/Greek) hit the right buckets', () {
      // É (Lu, U+00C9), é (Ll, U+00E9), Σ (Lu, U+03A3), σ (Ll, U+03C3).
      final out = PreludeAuthClient.validate(
        password: 'ÉéΣσ1!',
        against: const PreludePasswordCompliancy(
          minLength: 1,
          maxLength: 0,
          uppercase: 2,
          lowercase: 2,
          numbers: 1,
          symbols: 1,
        ),
      );
      expect(
        resultFor(out, PreludePasswordCompliancyCriterion.uppercase).actual,
        2,
        reason: 'É and Σ are both Lu',
      );
      expect(
        resultFor(out, PreludePasswordCompliancyCriterion.lowercase).actual,
        2,
        reason: 'é and σ are both Ll',
      );
      expect(out.valid, isTrue);
    });

    test('non-ASCII decimal digits (e.g. Devanagari) count as numbers', () {
      // U+0967 DEVANAGARI DIGIT ONE is general-category Nd.
      final out = PreludeAuthClient.validate(
        password: 'Aa१!aaaa',
        against: standard,
      );
      expect(
        resultFor(out, PreludePasswordCompliancyCriterion.numbers).actual,
        1,
      );
    });

    test('maxLength == 0 is the "no upper bound" sentinel', () {
      final long = 'A1!${'a' * 200}';
      final out = PreludeAuthClient.validate(
        password: long,
        against: const PreludePasswordCompliancy(
          minLength: 1,
          maxLength: 0,
          uppercase: 1,
          lowercase: 1,
          numbers: 1,
          symbols: 1,
        ),
      );
      expect(
        resultFor(out, PreludePasswordCompliancyCriterion.maxLength).valid,
        isTrue,
      );
      expect(out.valid, isTrue);
    });

    test('empty password reports zero on every count', () {
      final out = PreludeAuthClient.validate(
        password: '',
        against: standard,
      );
      expect(out.valid, isFalse);
      for (final r in out.results) {
        if (r.criterion == PreludePasswordCompliancyCriterion.maxLength) {
          // 0 length under maxLength=64 still satisfies the cap.
          expect(r.valid, isTrue);
        } else if (r.criterion == PreludePasswordCompliancyCriterion.minLength) {
          expect(r.actual, 0);
          expect(r.valid, isFalse);
        } else {
          expect(r.actual, 0);
        }
      }
    });

    test('symbols catch-all bucket covers punctuation and emoji', () {
      // 🚀 (astral), space, period are all "not Lu/Ll/Nd" → symbols.
      final out = PreludeAuthClient.validate(
        password: 'A1a 🚀.',
        against: const PreludePasswordCompliancy(
          minLength: 1,
          maxLength: 0,
          uppercase: 0,
          lowercase: 0,
          numbers: 0,
          symbols: 3,
        ),
      );
      expect(
        resultFor(out, PreludePasswordCompliancyCriterion.symbols).actual,
        3,
      );
      expect(out.valid, isTrue);
    });
  });
}
