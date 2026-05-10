import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prelude_flutter_session_sdk/prelude_flutter_session_sdk.dart';

/// Locks every typed [PreludeSessionException] subtype against the
/// platform-side error code emitted by the native plugin. If a new
/// case is added on the native side and not wired here, this suite
/// catches the drift before consumers do.
void main() {
  // Each entry is `<wire code, factory of the expected Dart type>`.
  final cases = <(String code, Type expected)>[
    ('bad_request', BadRequestException),
    ('unauthorized', UnauthorizedException),
    ('rate_limited', RateLimitedException),
    ('internal_server_error', InternalServerErrorException),
    ('missing_challenge_token', MissingChallengeTokenException),
    ('invalid_challenge_token', InvalidChallengeTokenException),
    ('expired_challenge_token', ExpiredChallengeTokenException),
    ('token_reused', TokenReusedException),
    ('invalid_otp_code', InvalidOTPCodeException),
    ('refresh_failed', RefreshFailedException),
    ('timeout', TimeoutException),
    ('invalid_configuration', InvalidConfigurationException),
    ('invalid_password', InvalidPasswordException),
    ('forbidden', ForbiddenException),
    ('insufficient_scope', InsufficientScopeException),
    ('not_found', NotFoundException),
    ('conflict', ConflictException),
    ('network', NetworkException),
  ];

  test('every documented code hydrates the matching Dart subtype', () {
    for (final (code, expected) in cases) {
      final ex = PreludeSessionException.fromPlatformException(
        PlatformException(code: code, message: 'boom'),
      );
      expect(
        ex.runtimeType,
        expected,
        reason: 'code `$code` should hydrate as $expected',
      );
      expect(ex.code, code);
    }
  });

  test('unknown codes hydrate as PreludeSessionGenericException', () {
    final ex = PreludeSessionException.fromPlatformException(
      PlatformException(code: 'flux_capacitor_failed', message: 'oops'),
    );
    expect(ex, isA<PreludeSessionGenericException>());
    // The generic case round-trips its raw code so consumers can
    // still discriminate when they need to.
    expect(ex.code, 'flux_capacitor_failed');
    expect(ex.message, 'oops');
  });

  test('TimeoutException carries a stable message regardless of input', () {
    final ex = PreludeSessionException.fromPlatformException(
      PlatformException(code: 'timeout', message: 'ignored'),
    );
    expect(ex, isA<TimeoutException>());
    expect(ex.message, 'Request timed out');
  });

  test('toString includes the runtimeType + code + message', () {
    final ex = const UnauthorizedException('bad creds');
    expect(ex.toString(), 'UnauthorizedException(unauthorized): bad creds');
  });
}
