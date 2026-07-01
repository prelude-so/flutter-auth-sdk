import 'package:flutter_test/flutter_test.dart';
import 'package:prelude_flutter_auth_sdk/prelude_flutter_auth_sdk.dart';

/// Wire-form and decode tests for the OAuth login surface. The
/// native plugin's encoder is the source of truth; these cases
/// exercise the Dart-side options encoding and the tagged-result
/// decoder against payloads shaped exactly like that encoder.
void main() {
  group('OAuthProvider', () {
    test('wire values match the API spelling', () {
      expect(OAuthProvider.google.wireValue, 'google');
      expect(OAuthProvider.apple.wireValue, 'apple');
      expect(OAuthProvider.microsoft.wireValue, 'microsoft');
      expect(OAuthProvider.github.wireValue, 'github');
      expect(OAuthProvider.okta.wireValue, 'okta');
      expect(OAuthProvider.facebook.wireValue, 'facebook');
    });
  });

  group('OAuthLoginOptions.toJson', () {
    test('encodes provider, redirect, and ephemeral flag', () {
      final json = const OAuthLoginOptions(
        provider: OAuthProvider.google,
        redirectUri: 'prelude-demo://oauth-callback',
        prefersEphemeralSession: true,
      ).toJson();
      expect(json, {
        'provider': 'google',
        'redirectUri': 'prelude-demo://oauth-callback',
        'prefersEphemeralSession': true,
      });
    });

    test('ephemeral defaults to false', () {
      final json = const OAuthLoginOptions(
        provider: OAuthProvider.apple,
        redirectUri: 'prelude-demo://oauth-callback',
      ).toJson();
      expect(json['prefersEphemeralSession'], false);
    });
  });

  group('InitiateOAuthLoginOptions.toJson', () {
    test('encodes provider and redirect only', () {
      final json = const InitiateOAuthLoginOptions(
        provider: OAuthProvider.microsoft,
        redirectUri: 'https://app.example/callback',
      ).toJson();
      expect(json, {
        'provider': 'microsoft',
        'redirectUri': 'https://app.example/callback',
      });
    });
  });

  group('FinalizeOAuthLoginResult.fromJson', () {
    test('decodes logged_in into OAuthLoggedIn with the user', () {
      final result = FinalizeOAuthLoginResult.fromJson({
        'kind': 'logged_in',
        'user': {
          'accessToken': 'eyJ.token',
          'profile': {
            'userID': 'usr_1',
            'sessionID': 'ses_1',
            'extras': <String, Object?>{},
          },
        },
      });
      expect(result, isA<OAuthLoggedIn>());
      final user = (result as OAuthLoggedIn).user;
      expect(user.accessToken, 'eyJ.token');
      expect(user.profile.userID, 'usr_1');
    });

    test('decodes otp_required into a challenge handle with email', () {
      final result = FinalizeOAuthLoginResult.fromJson({
        'kind': 'otp_required',
        'challengeID': 'cid_123',
        'email': 'a@b.c',
      });
      expect(result, isA<OAuthOtpRequired>());
      final otp = result as OAuthOtpRequired;
      expect(otp.challenge.challengeID, 'cid_123');
      expect(otp.email, 'a@b.c');
    });

    test('otp_required tolerates a null email', () {
      final result = FinalizeOAuthLoginResult.fromJson({
        'kind': 'otp_required',
        'challengeID': 'cid_123',
        'email': null,
      });
      expect((result as OAuthOtpRequired).email, isNull);
    });

    test('OAuthEmailChallenge.toString carries only the cache key', () {
      final otp = FinalizeOAuthLoginResult.fromJson({
        'kind': 'otp_required',
        'challengeID': 'cid_123',
        'email': 'a@b.c',
      }) as OAuthOtpRequired;
      expect(otp.challenge.toString(), 'OAuthEmailChallenge(cid_123)');
    });

    test('throws on an unknown kind', () {
      expect(
        () => FinalizeOAuthLoginResult.fromJson({'kind': 'who_knows'}),
        throwsArgumentError,
      );
    });
  });
}
