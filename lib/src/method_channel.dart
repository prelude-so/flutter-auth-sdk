import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_interface.dart';
import 'types/errors.dart';
import 'types/migrate.dart';
import 'types/oauth.dart';
import 'types/otp.dart';
import 'types/password.dart';
import 'types/profile.dart';
import 'types/redacted_string.dart';
import 'types/sessions.dart';
import 'types/step_up.dart';
import 'types/user.dart';

/// `MethodChannel`-based implementation of
/// [PreludeAuthClientPlatform]. The channel name matches the
/// one registered by the iOS and Android plugin shells.
class MethodChannelPreludeAuthClient extends PreludeAuthClientPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('prelude_so_flutter_auth_sdk');

  /// Wrap one channel invocation with a single error-translation
  /// hop so every public method shares the same code path. The
  /// platform-side codes (`unauthorized`, `invalid_otp_code`, …)
  /// match [PreludeAuthException.fromPlatformException].
  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await methodChannel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw PreludeAuthException.fromPlatformException(e);
    }
  }

  /// Convenience for routes that always return a structured map.
  ///
  /// A null reply here is a Dart↔native contract violation, not an
  /// Auth-API failure (the native plugin either returns the
  /// encoded value or surfaces a `PlatformException`). It surfaces
  /// as a [StateError] so consumers catching [PreludeAuthException]
  /// don't accidentally swallow it.
  Future<Map<Object?, Object?>> _invokeMap(
    String method,
    Map<String, Object?> args,
  ) async {
    final raw = await _invoke<Map<Object?, Object?>>(method, args);
    if (raw == null) {
      throw StateError(
        'PreludeAuth bridge returned null for `$method`; '
        'expected a non-null map.',
      );
    }
    return raw;
  }

  @override
  Future<String?> getPlatformVersion() {
    return _invoke<String>('getPlatformVersion');
  }

  @override
  Future<void> dispose({required String handle}) async {
    await _invoke<void>('dispose', {'handle': handle});
  }

  Map<String, Object?> _baseArgs(String handle, ClientConfig config) => {
    'handle': handle,
    'config': config.toJson(),
  };

  @override
  Future<void> startOTPLogin({
    required String handle,
    required ClientConfig config,
    required StartOTPLoginOptions options,
  }) async {
    await _invoke<void>('startOTPLogin', {
      ..._baseArgs(handle, config),
      'options': options.toJson(),
    });
  }

  @override
  Future<void> resendOTP({
    required String handle,
    required ClientConfig config,
  }) async {
    await _invoke<void>('resendOTP', _baseArgs(handle, config));
  }

  @override
  Future<PreludeUser> checkOTP({
    required String handle,
    required ClientConfig config,
    required String code,
  }) async {
    final raw = await _invokeMap('checkOTP', {
      ..._baseArgs(handle, config),
      'code': code,
    });
    return PreludeUser.fromJson(raw);
  }

  @override
  Future<PreludeUser> loginWithPassword({
    required String handle,
    required ClientConfig config,
    required LoginWithPasswordOptions options,
  }) async {
    final raw = await _invokeMap('loginWithPassword', {
      ..._baseArgs(handle, config),
      'options': options.toJson(),
    });
    return PreludeUser.fromJson(raw);
  }

  @override
  Future<PreludePasswordCompliancy> passwordCompliancy({
    required String handle,
    required ClientConfig config,
  }) async {
    final raw = await _invokeMap('passwordCompliancy', _baseArgs(handle, config));
    return PreludePasswordCompliancy.fromJson(raw);
  }

  @override
  Future<void> changePassword({
    required String handle,
    required ClientConfig config,
    required RedactedString newPassword,
  }) async {
    await _invoke<void>('changePassword', {
      ..._baseArgs(handle, config),
      // Unwrap exactly here, on the way to the channel — the only
      // point inside the SDK where the secret needs to be plain.
      'newPassword': newPassword.value,
    });
  }

  @override
  Future<bool> canChangePassword({
    required String handle,
    required ClientConfig config,
  }) async {
    // Native side always returns a `Bool` — null is a bridge
    // contract violation, not a "no". Surface it as `StateError`
    // so a real bug doesn't masquerade as a false-negative.
    final raw = await _invoke<bool>('canChangePassword', _baseArgs(handle, config));
    if (raw == null) {
      throw StateError(
        'PreludeAuth bridge returned null for `canChangePassword`; '
        'expected a non-null bool.',
      );
    }
    return raw;
  }

  @override
  Future<PreludeUser> migrate({
    required String handle,
    required ClientConfig config,
    required MigrateOptions options,
  }) async {
    final raw = await _invokeMap('migrate', {
      ..._baseArgs(handle, config),
      'options': options.toJson(),
    });
    return PreludeUser.fromJson(raw);
  }

  @override
  Future<FinalizeOAuthLoginResult> loginWithOAuth({
    required String handle,
    required ClientConfig config,
    required OAuthLoginOptions options,
  }) async {
    final raw = await _invokeMap('loginWithOAuth', {
      ..._baseArgs(handle, config),
      'options': options.toJson(),
    });
    return FinalizeOAuthLoginResult.fromJson(raw);
  }

  @override
  Future<Uri> initiateOAuthLogin({
    required String handle,
    required ClientConfig config,
    required InitiateOAuthLoginOptions options,
  }) async {
    // Native side always returns a non-null URL string; a null
    // reply is a bridge contract violation, not an Auth-API
    // failure. Surface as StateError so it isn't swallowed as a
    // PreludeAuthException.
    final raw = await _invoke<String>('initiateOAuthLogin', {
      ..._baseArgs(handle, config),
      'options': options.toJson(),
    });
    if (raw == null) {
      throw StateError(
        'PreludeAuth bridge returned null for `initiateOAuthLogin`; '
        'expected a non-null URL string.',
      );
    }
    return Uri.parse(raw);
  }

  @override
  Future<FinalizeOAuthLoginResult> finalizeOAuthLogin({
    required String handle,
    required ClientConfig config,
    required String challengeToken,
  }) async {
    final raw = await _invokeMap('finalizeOAuthLogin', {
      ..._baseArgs(handle, config),
      'challengeToken': challengeToken,
    });
    return FinalizeOAuthLoginResult.fromJson(raw);
  }

  @override
  Future<PreludeUser> checkOAuthEmailOTP({
    required String handle,
    required ClientConfig config,
    required OAuthEmailChallenge challenge,
    required String code,
  }) async {
    // Only the [challengeID] travels over the channel; the
    // verification token lives in the native plugin's per-handle
    // cache. The bridge resolves it via [challengeID] before
    // firing /otp/check.
    final raw = await _invokeMap('checkOAuthEmailOTP', {
      ..._baseArgs(handle, config),
      'challengeID': challenge.challengeID,
      'code': code,
    });
    return PreludeUser.fromJson(raw);
  }

  @override
  Future<PreludeUser> refresh({
    required String handle,
    required ClientConfig config,
  }) async {
    final raw = await _invokeMap('refresh', _baseArgs(handle, config));
    return PreludeUser.fromJson(raw);
  }

  @override
  Future<void> logout({
    required String handle,
    required ClientConfig config,
  }) async {
    await _invoke<void>('logout', _baseArgs(handle, config));
  }

  @override
  Future<void> invalidateSession({
    required String handle,
    required ClientConfig config,
  }) async {
    await _invoke<void>('invalidateSession', _baseArgs(handle, config));
  }

  @override
  Future<PreludeListSessionsResponse> listSessions({
    required String handle,
    required ClientConfig config,
    required PreludeListSessionsOptions options,
  }) async {
    final raw = await _invokeMap('listSessions', {
      ..._baseArgs(handle, config),
      'options': options.toJson(),
    });
    return PreludeListSessionsResponse.fromJson(raw);
  }

  @override
  Future<void> revokeSessions({
    required String handle,
    required ClientConfig config,
    required PreludeRevokeTarget target,
  }) async {
    await _invoke<void>('revokeSessions', {
      ..._baseArgs(handle, config),
      'target': target.toJson(),
    });
  }

  @override
  Future<StepUpChallenge> requestStepUp({
    required String handle,
    required ClientConfig config,
    required String scope,
    Map<String, String>? metadata,
  }) async {
    final raw = await _invokeMap('requestStepUp', {
      ..._baseArgs(handle, config),
      'scope': scope,
      'metadata': ?metadata,
    });
    return StepUpChallenge.fromJson(raw);
  }

  @override
  Future<void> sendStepUpOTP({
    required String handle,
    required ClientConfig config,
    required StepUpChallenge challenge,
  }) async {
    // Only the [challengeID] travels over the channel; the token
    // + expiry live in the native plugin's per-handle cache. The
    // bridge resolves them via [challengeID] before firing /otp.
    await _invoke<void>('sendStepUpOTP', {
      ..._baseArgs(handle, config),
      'challengeID': challenge.challengeID,
    });
  }

  @override
  Future<StepUpChallenge?> submitStepUpOTP({
    required String handle,
    required ClientConfig config,
    required StepUpChallenge challenge,
    required String code,
  }) async {
    // Only the [challengeID] travels over the channel; the token
    // + expiry live in the native plugin's per-handle cache. The
    // bridge resolves them via [challengeID] on submit.
    final raw = await _invoke<Map<Object?, Object?>>('submitStepUpOTP', {
      ..._baseArgs(handle, config),
      'challengeID': challenge.challengeID,
      'code': code,
    });
    if (raw == null) return null;
    return StepUpChallenge.fromJson(raw);
  }

  @override
  Future<StepUpChallenge?> getActiveStepUp({
    required String handle,
    required ClientConfig config,
  }) async {
    final raw = await _invoke<Map<Object?, Object?>>(
      'getActiveStepUp',
      _baseArgs(handle, config),
    );
    return raw == null ? null : StepUpChallenge.fromJson(raw);
  }

  @override
  Future<PreludeProfile?> getProfile({
    required String handle,
    required ClientConfig config,
  }) async {
    final raw = await _invoke<Map<Object?, Object?>>(
      'getProfile',
      _baseArgs(handle, config),
    );
    return raw == null ? null : PreludeProfile.fromJson(raw);
  }

  @override
  Future<String?> getSessionID({
    required String handle,
    required ClientConfig config,
  }) {
    return _invoke<String>('getSessionID', _baseArgs(handle, config));
  }

  @override
  Future<String?> getAccessToken({
    required String handle,
    required ClientConfig config,
  }) {
    return _invoke<String>('getAccessToken', _baseArgs(handle, config));
  }

  @override
  Future<DateTime?> getAccessTokenExpiresAt({
    required String handle,
    required ClientConfig config,
  }) async {
    final unix = await _invoke<int>(
      'getAccessTokenExpiresAt',
      _baseArgs(handle, config),
    );
    return unix == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);
  }
}
