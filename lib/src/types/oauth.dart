import 'user.dart';

/// Identity providers supported for OAuth login.
enum OAuthProvider {
  google('google'),
  apple('apple'),
  microsoft('microsoft'),
  github('github'),
  okta('okta'),
  facebook('facebook');

  const OAuthProvider(this.wireValue);

  /// Wire string used by the Prelude API.
  final String wireValue;
}

/// Options for [PreludeAuthClient.loginWithOAuth].
class OAuthLoginOptions {
  const OAuthLoginOptions({
    required this.provider,
    required this.redirectUri,
    this.prefersEphemeralSession = false,
  });

  /// Provider to authenticate against.
  final OAuthProvider provider;

  /// Where the provider redirects once authentication completes.
  /// Must use the app's custom URL scheme (e.g.
  /// `myapp://oauth-callback`) and be allowlisted by the app's
  /// configuration.
  final String redirectUri;

  /// When `true` the web session shares no cookies with the
  /// system browser, so every login starts clean. iOS only;
  /// ignored on Android. Defaults to `false`.
  final bool prefersEphemeralSession;

  Map<String, Object?> toJson() => {
    'provider': provider.wireValue,
    'redirectUri': redirectUri,
    'prefersEphemeralSession': prefersEphemeralSession,
  };
}

/// Options for [PreludeAuthClient.initiateOAuthLogin].
class InitiateOAuthLoginOptions {
  const InitiateOAuthLoginOptions({
    required this.provider,
    required this.redirectUri,
  });

  /// Provider to authenticate against.
  final OAuthProvider provider;

  /// Where the server redirects once authentication completes.
  /// Must be allowlisted by the app's configuration.
  final String redirectUri;

  Map<String, Object?> toJson() => {
    'provider': provider.wireValue,
    'redirectUri': redirectUri,
  };
}

/// Outcome of redeeming an OAuth login callback.
sealed class FinalizeOAuthLoginResult {
  const FinalizeOAuthLoginResult();

  /// Decode the tagged wire form produced by the native plugin.
  factory FinalizeOAuthLoginResult.fromJson(Map<Object?, Object?> json) {
    switch (json['kind']) {
      case 'logged_in':
        return OAuthLoggedIn(
          PreludeUser.fromJson(
            Map<Object?, Object?>.from(json['user']! as Map),
          ),
        );
      case 'otp_required':
        return OAuthOtpRequired(
          challenge: OAuthEmailChallenge._(json['challengeID']! as String),
          email: json['email'] as String?,
        );
      default:
        throw ArgumentError.value(
          json['kind'],
          'kind',
          'unknown FinalizeOAuthLoginResult kind',
        );
    }
  }
}

/// Session established.
class OAuthLoggedIn extends FinalizeOAuthLoginResult {
  const OAuthLoggedIn(this.user);

  final PreludeUser user;
}

/// Provider email unverified; a one-time code was sent to [email].
/// Redeem [challenge] via [PreludeAuthClient.checkOAuthEmailOTP] with
/// the code the user receives.
class OAuthOtpRequired extends FinalizeOAuthLoginResult {
  const OAuthOtpRequired({required this.challenge, this.email});

  /// Resumable handle for the email-verification step.
  final OAuthEmailChallenge challenge;

  /// Address the code was sent to, when the server discloses it.
  final String? email;
}

/// An OAuth-email-link verification awaiting its one-time code.
/// Returned in [OAuthOtpRequired] and redeemed by
/// [PreludeAuthClient.checkOAuthEmailOTP].
///
/// The verification token stays on the native side, keyed by
/// [challengeID] in a per-client cache; only [challengeID] travels
/// over the channel, so a Dart-side log or debugger never observes
/// the bearer credential. Consumers receive a handle from the SDK
/// and pass it back unchanged — the constructor is library-private,
/// so instances can't be forged from Dart.
class OAuthEmailChallenge {
  const OAuthEmailChallenge._(this.challengeID);

  /// Native cache key for this attempt. Carries no secret material.
  final String challengeID;

  @override
  String toString() => 'OAuthEmailChallenge($challengeID)';
}
