import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel.dart';
import 'types/endpoint.dart';
import 'types/migrate.dart';
import 'types/oauth.dart';
import 'types/otp.dart';
import 'types/passkey.dart';
import 'types/password.dart';
import 'types/profile.dart';
import 'types/redacted_string.dart';
import 'types/sessions.dart';
import 'types/step_up.dart';
import 'types/user.dart';

/// Platform interface for [PreludeAuthClient].
///
/// Concrete implementations extend this class. Tests substitute a
/// mock by assigning to [instance]; `verifyToken` keeps rogue
/// subclasses out.
///
/// Every method takes the calling client's `handle` (a UUID
/// minted by the Dart constructor) plus its config snapshot. The
/// native plugin lazily creates a `PreludeAuthClient` per
/// handle on first call and reuses it across subsequent calls —
/// so DPoP keys, refresh tokens, and the access-token cache stay
/// stable for the lifetime of the Dart instance.
abstract class PreludeAuthClientPlatform extends PlatformInterface {
  PreludeAuthClientPlatform() : super(token: _token);

  static final Object _token = Object();

  static PreludeAuthClientPlatform _instance =
      MethodChannelPreludeAuthClient();

  static PreludeAuthClientPlatform get instance => _instance;

  static set instance(PreludeAuthClientPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Native SDK platform version. Smoke-test for the channel.
  Future<String?> getPlatformVersion();

  // ------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------

  /// Release native state owned by [handle]. After this returns
  /// any further call with [handle] re-creates the native client
  /// from scratch.
  Future<void> dispose({required String handle});

  // ------------------------------------------------------------
  // OTP
  // ------------------------------------------------------------

  Future<void> startOTPLogin({
    required String handle,
    required ClientConfig config,
    required StartOTPLoginOptions options,
  });

  Future<void> resendOTP({
    required String handle,
    required ClientConfig config,
  });

  Future<PreludeUser> checkOTP({
    required String handle,
    required ClientConfig config,
    required String code,
  });

  // ------------------------------------------------------------
  // Password
  // ------------------------------------------------------------

  Future<PreludeUser> loginWithPassword({
    required String handle,
    required ClientConfig config,
    required LoginWithPasswordOptions options,
  });

  Future<PreludePasswordCompliancy> passwordCompliancy({
    required String handle,
    required ClientConfig config,
  });

  // Note: there is intentionally no `validatePassword` on the
  // platform interface. Classification is pure and runs in Dart
  // via [PreludeAuthClient.validate]; the only thing platforms
  // need to surface is the rules ([passwordCompliancy]).

  Future<void> changePassword({
    required String handle,
    required ClientConfig config,
    required RedactedString newPassword,
  });

  Future<bool> canChangePassword({
    required String handle,
    required ClientConfig config,
  });

  // ------------------------------------------------------------
  // Migration
  // ------------------------------------------------------------

  Future<PreludeUser> migrate({
    required String handle,
    required ClientConfig config,
    required MigrateOptions options,
  });

  // ------------------------------------------------------------
  // Social / OAuth login
  // ------------------------------------------------------------

  Future<FinalizeOAuthLoginResult> loginWithOAuth({
    required String handle,
    required ClientConfig config,
    required OAuthLoginOptions options,
  });

  Future<Uri> initiateOAuthLogin({
    required String handle,
    required ClientConfig config,
    required InitiateOAuthLoginOptions options,
  });

  Future<FinalizeOAuthLoginResult> finalizeOAuthLogin({
    required String handle,
    required ClientConfig config,
    required String challengeToken,
  });

  Future<PreludeUser> checkOAuthEmailOTP({
    required String handle,
    required ClientConfig config,
    required OAuthEmailChallenge challenge,
    required String code,
  });

  // ------------------------------------------------------------
  // Refresh / logout / invalidate
  // ------------------------------------------------------------

  Future<PreludeUser> refresh({
    required String handle,
    required ClientConfig config,
  });

  Future<void> logout({required String handle, required ClientConfig config});

  Future<void> invalidateSession({
    required String handle,
    required ClientConfig config,
  });

  // ------------------------------------------------------------
  // Manage sessions (list / revoke)
  // ------------------------------------------------------------

  Future<PreludeListSessionsResponse> listSessions({
    required String handle,
    required ClientConfig config,
    required PreludeListSessionsOptions options,
  });

  Future<void> revokeSessions({
    required String handle,
    required ClientConfig config,
    required PreludeRevokeTarget target,
  });

  // ------------------------------------------------------------
  // Step-up
  // ------------------------------------------------------------

  Future<StepUpChallenge> requestStepUp({
    required String handle,
    required ClientConfig config,
    required String scope,
    Map<String, String>? metadata,
  });

  Future<void> sendStepUpOTP({
    required String handle,
    required ClientConfig config,
    required StepUpChallenge challenge,
  });

  Future<StepUpChallenge?> submitStepUpOTP({
    required String handle,
    required ClientConfig config,
    required StepUpChallenge challenge,
    required String code,
  });

  Future<StepUpChallenge?> getActiveStepUp({
    required String handle,
    required ClientConfig config,
  });

  Future<StepUpChallenge?> continueStepUpWithPasskey({
    required String handle,
    required ClientConfig config,
    required StepUpChallenge challenge,
  });

  // ------------------------------------------------------------
  // Passkey
  // ------------------------------------------------------------

  Future<PasskeyRegistrationResult> registerPasskey({
    required String handle,
    required ClientConfig config,
    required RegisterPasskeyOptions options,
  });

  Future<PreludeUser> loginWithPasskey({
    required String handle,
    required ClientConfig config,
    required PasskeyLoginOptions options,
  });

  Future<List<PreludePasskeyCredential>> listPasskeys({
    required String handle,
    required ClientConfig config,
  });

  Future<void> renamePasskey({
    required String handle,
    required ClientConfig config,
    required String credentialID,
    required String nickname,
  });

  Future<void> deletePasskey({
    required String handle,
    required ClientConfig config,
    required String credentialID,
  });

  // ------------------------------------------------------------
  // Cached session readers
  // ------------------------------------------------------------

  Future<PreludeProfile?> getProfile({
    required String handle,
    required ClientConfig config,
  });

  Future<String?> getSessionID({
    required String handle,
    required ClientConfig config,
  });

  Future<String?> getAccessToken({
    required String handle,
    required ClientConfig config,
  });

  Future<DateTime?> getAccessTokenExpiresAt({
    required String handle,
    required ClientConfig config,
  });
}

/// Snapshot of the [PreludeAuthClient] constructor args. Sent
/// alongside every call so the native plugin can lazily construct
/// the underlying client on first use without an explicit init
/// step.
class ClientConfig {
  const ClientConfig({
    required this.endpoint,
    required this.hostOverride,
    required this.timeoutSeconds,
    required this.allowInsecureTLS,
    this.signalsKeyOverride,
  });

  final Endpoint endpoint;
  final String? hostOverride;
  final double timeoutSeconds;
  final bool allowInsecureTLS;

  /// Optional Prelude signals SDK key. When non-null, the native
  /// plugin uses this in place of the platform-manifest entry
  /// (`PreludeSDKKey` on iOS, `so.prelude.sdk_key` on Android).
  /// Null is the common case — keys belong in the manifest so
  /// they don't leak across platform bundles.
  final String? signalsKeyOverride;

  Map<String, Object?> toJson() => {
    'endpoint': endpoint.toJson(),
    'hostOverride': hostOverride,
    'timeoutSeconds': timeoutSeconds,
    'allowInsecureTLS': allowInsecureTLS,
    'signalsKeyOverride': signalsKeyOverride,
  };
}
