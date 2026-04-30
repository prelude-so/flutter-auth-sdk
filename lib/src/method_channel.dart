import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_interface.dart';
import 'types/errors.dart';
import 'types/otp.dart';
import 'types/password.dart';
import 'types/profile.dart';
import 'types/redacted_string.dart';
import 'types/step_up.dart';
import 'types/user.dart';

/// `MethodChannel`-based implementation of
/// [PreludeSessionClientPlatform]. The channel name matches the
/// one registered by the iOS and Android plugin shells.
class MethodChannelPreludeSessionClient extends PreludeSessionClientPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('prelude_so_flutter_session_sdk');

  /// Wrap one channel invocation with a single error-translation
  /// hop so every public method shares the same code path. The
  /// platform-side codes (`unauthorized`, `invalid_otp_code`, …)
  /// match [PreludeSessionException.fromPlatformException].
  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await methodChannel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw PreludeSessionException.fromPlatformException(e);
    }
  }

  /// Convenience for routes that always return a structured map.
  ///
  /// A null reply here is a Dart↔native contract violation, not a
  /// session-API failure (the native plugin either returns the
  /// encoded value or surfaces a `PlatformException`). It surfaces
  /// as a [StateError] so consumers catching [PreludeSessionException]
  /// to handle expected API failures don't accidentally swallow
  /// internal bridge bugs.
  Future<Map<Object?, Object?>> _invokeMap(
    String method,
    Map<String, Object?> args,
  ) async {
    final raw = await _invoke<Map<Object?, Object?>>(method, args);
    if (raw == null) {
      throw StateError(
        'PreludeSession bridge returned null for `$method`; '
        'expected a non-null map. This is a bridge bug — please '
        'file an issue with the call site.',
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
  Future<StepUpChallenge> requestStepUp({
    required String handle,
    required ClientConfig config,
    required String scope,
  }) async {
    final raw = await _invokeMap('requestStepUp', {
      ..._baseArgs(handle, config),
      'scope': scope,
    });
    return StepUpChallenge.fromJson(raw);
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
