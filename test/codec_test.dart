import 'package:flutter_test/flutter_test.dart';
import 'package:prelude_flutter_session_sdk/prelude_flutter_session_sdk.dart';

/// Round-trip tests for every wire-form value the bridge sends or
/// receives. The native plugin's encoder is the source of truth;
/// these cases exercise the Dart-side decoders against payloads
/// shaped exactly like that encoder produces.
void main() {
  group('PreludeJSONValue', () {
    test('round-trips every variant', () {
      // One representative per case, plus nesting so encoders
      // reach their recursion paths.
      final original = PreludeJSONValue.object({
        'name': const PreludeJSONValue.string('alice'),
        'age': const PreludeJSONValue.integer(42),
        'score': const PreludeJSONValue.double_(3.14),
        'active': const PreludeJSONValue.boolean(true),
        'tags': const PreludeJSONValue.array([
          PreludeJSONValue.string('admin'),
          PreludeJSONValue.string('beta'),
        ]),
        'metadata': const PreludeJSONValue.null_(),
      });

      final json = original.toJson();
      final decoded = PreludeJSONValue.fromJson(json);

      expect(decoded, equals(original));
    });

    test('keeps int and double distinct (no precision loss)', () {
      // 64-bit subject claims would lose precision if int → double
      // coercion happened. Guard the kind tagging.
      const big = PreludeJSONValue.integer(9007199254740993); // 2^53 + 1
      final round = PreludeJSONValue.fromJson(big.toJson());
      expect(round, isA<PreludeJSONInt>());
      expect((round as PreludeJSONInt).value, 9007199254740993);

      const dbl = PreludeJSONValue.double_(2.0);
      final roundDbl = PreludeJSONValue.fromJson(dbl.toJson());
      expect(roundDbl, isA<PreludeJSONDouble>());
    });

    test('toPlain strips the tagging', () {
      const v = PreludeJSONValue.object({
        'a': PreludeJSONValue.integer(1),
        'b': PreludeJSONValue.array([PreludeJSONValue.boolean(false)]),
      });
      expect(v.toPlain(), {
        'a': 1,
        'b': [false],
      });
    });

    test('rejects malformed payload', () {
      expect(
        () => PreludeJSONValue.fromJson({'kind': 'wat', 'value': 1}),
        throwsArgumentError,
      );
      expect(
        () => PreludeJSONValue.fromJson('not a map'),
        throwsArgumentError,
      );
    });
  });

  group('PreludeIdentifier', () {
    test('round-trips through wire form', () {
      final phone = PreludeIdentifier.phoneNumber('+15555550123');
      final email = PreludeIdentifier.emailAddress('alice@example.com');

      expect(phone, PreludeIdentifier.fromJson(phone.toJson()));
      expect(email, PreludeIdentifier.fromJson(email.toJson()));

      // Wire keys match what the native encoders emit.
      expect(phone.toJson(), {
        'type': 'phone_number',
        'value': '+15555550123',
      });
      expect(email.toJson(), {
        'type': 'email_address',
        'value': 'alice@example.com',
      });
    });

    test('rejects unknown identifier types', () {
      expect(
        () => PreludeIdentifier.fromJson({'type': 'iban', 'value': 'x'}),
        throwsArgumentError,
      );
    });
  });

  group('PreludeProfile', () {
    test('decodes JSON-tagged extras', () {
      final wire = {
        'userID': 'usr_123',
        'sessionID': 'ses_abc',
        'extras': {
          'plan': {'kind': 'string', 'value': 'pro'},
          'seats': {'kind': 'int', 'value': 5},
        },
      };
      final profile = PreludeProfile.fromJson(wire);

      expect(profile.userID, 'usr_123');
      expect(profile.sessionID, 'ses_abc');
      expect(profile.extras['plan'], const PreludeJSONValue.string('pro'));
      expect(profile.extras['seats'], const PreludeJSONValue.integer(5));
    });

    test('handles null sub / sid (anonymous profile)', () {
      final profile = PreludeProfile.fromJson({
        'userID': null,
        'sessionID': null,
        'extras': const <String, Object?>{},
      });
      expect(profile.userID, isNull);
      expect(profile.sessionID, isNull);
      expect(profile.extras, isEmpty);
    });
  });

  group('PreludeUser', () {
    test('round-trips through fromJson', () {
      final user = PreludeUser(
        accessToken: 'eyJ.access.token',
        profile: const PreludeProfile(
          userID: 'usr_1',
          sessionID: 'ses_1',
          extras: {'flag': PreludeJSONValue.boolean(true)},
        ),
      );

      final hydrated = PreludeUser.fromJson(user.toJson());
      expect(hydrated, user);
    });

    test('toString redacts the access token', () {
      const user = PreludeUser(
        accessToken: 'eyJ.something.secret',
        profile: PreludeProfile(),
      );
      // Render the token's char-count, not the token itself.
      expect(user.toString(), contains('<redacted ${'eyJ.something.secret'.length} chars>'));
      expect(user.toString(), isNot(contains('secret')));
    });
  });

  group('PreludePasswordCompliancy', () {
    test('round-trips through fromJson', () {
      const c = PreludePasswordCompliancy(
        minLength: 8,
        maxLength: 64,
        uppercase: 1,
        lowercase: 1,
        numbers: 1,
        symbols: 0,
      );
      expect(PreludePasswordCompliancy.fromJson(c.toJson()), c);
    });
  });

  group('Endpoint', () {
    test('default → tagged map', () {
      expect(Endpoint.defaultEndpoint.toJson(), {'kind': 'default'});
    });

    test('custom carries the address', () {
      const e = Endpoint.custom('https://staging.example.com');
      expect(e.toJson(), {
        'kind': 'custom',
        'address': 'https://staging.example.com',
      });
    });
  });

  group('StartOTPLoginOptions', () {
    test('toJson includes nested identifier and config id', () {
      final options = StartOTPLoginOptions(
        identifier: PreludeIdentifier.phoneNumber('+15555550123'),
        loginConfigID: 'cfg_email_only',
      );
      expect(options.toJson(), {
        'identifier': {'type': 'phone_number', 'value': '+15555550123'},
        'loginConfigID': 'cfg_email_only',
      });
    });
  });

  group('LoginWithPasswordOptions', () {
    test('toJson sends the unwrapped password value', () {
      final options = LoginWithPasswordOptions(
        emailAddress: 'alice@example.com',
        password: 's3cr3t',
      );
      expect(options.toJson(), {
        'emailAddress': 'alice@example.com',
        'password': 's3cr3t',
      });
    });

    test('toString redacts the password', () {
      final options = LoginWithPasswordOptions(
        emailAddress: 'alice@example.com',
        password: 's3cr3t',
      );
      expect(options.toString(), contains('<redacted>'));
      expect(options.toString(), isNot(contains('s3cr3t')));
    });

    test('redacted ctor accepts a pre-wrapped value', () {
      const options = LoginWithPasswordOptions.redacted(
        emailAddress: 'alice@example.com',
        password: RedactedString('s3cr3t'),
      );
      expect(options.password.value, 's3cr3t');
    });
  });

  group('StepUpChallenge wire shape', () {
    test('toJson exposes only public metadata — never the JWT', () {
      // Reconstruct the way the native plugins emit one. The wire
      // shape MUST NOT carry a token or expiresAt; otherwise the
      // bridge has regressed and the bearer challenge is observable
      // from Dart land.
      final wire = {
        'status': 'continue',
        'challengeID': 'chal_abc',
        'currentStep': 'verify_email',
        'requestedScope': 'prld:pwd:write',
      };
      final challenge = StepUpChallenge.fromJson(wire);
      final round = challenge.toJson();

      expect(round.keys.toSet(), {
        'status',
        'challengeID',
        'currentStep',
        'requestedScope',
      });
      // Belt-and-suspenders against silent regression: no key
      // anywhere in the round-tripped payload should look like
      // a token or an expiry.
      expect(round.keys, isNot(contains('_handle')));
      expect(round.keys, isNot(contains('token')));
      expect(round.keys, isNot(contains('expiresAt')));
    });

    test('decodes the three statuses', () {
      for (final wireStatus in const ['continue', 'review', 'block']) {
        final challenge = StepUpChallenge.fromJson({
          'status': wireStatus,
          'challengeID': 'cid',
          'currentStep': null,
          'requestedScope': 'scope',
        });
        expect(challenge.status.wireValue, wireStatus);
      }
    });
  });
}
