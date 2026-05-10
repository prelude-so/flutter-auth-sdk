import 'package:flutter/services.dart';

/// Base type for every error thrown by [PreludeSessionClient].
///
/// A helper [PreludeSessionException.fromPlatformException] decodes
/// the structured `code` / `message` / `details` produced by the
/// native plugin into the matching Dart subtype, so consumers can
/// `try/catch` against specific cases (`InvalidOTPCodeException`,
/// `InsufficientScopeException`, …) instead of inspecting raw
/// channel error codes.
sealed class PreludeSessionException implements Exception {
  const PreludeSessionException(this.message);

  /// Human-readable message.
  final String message;

  /// Stable code identifying the case. Used by the bridge for
  /// round-tripping and for consumer matching when needed.
  String get code;

  @override
  String toString() => '$runtimeType($code): $message';

  /// Decode a [PlatformException] thrown by the method channel
  /// into the matching typed subtype. Falls back to
  /// [PreludeSessionGenericException] when the code isn't
  /// recognised — keeping forward compatibility cheap.
  static PreludeSessionException fromPlatformException(PlatformException e) {
    final message = e.message ?? '';
    switch (e.code) {
      case 'bad_request':
        return BadRequestException(message);
      case 'unauthorized':
        return UnauthorizedException(message);
      case 'rate_limited':
        return RateLimitedException(message);
      case 'internal_server_error':
        return InternalServerErrorException(message);
      case 'missing_challenge_token':
        return MissingChallengeTokenException(message);
      case 'invalid_challenge_token':
        return InvalidChallengeTokenException(message);
      case 'expired_challenge_token':
        return ExpiredChallengeTokenException(message);
      case 'token_reused':
        return TokenReusedException(message);
      case 'invalid_otp_code':
        return InvalidOTPCodeException(message);
      case 'refresh_failed':
        return RefreshFailedException(message);
      case 'timeout':
        return const TimeoutException();
      case 'invalid_configuration':
        return InvalidConfigurationException(message);
      case 'invalid_password':
        return InvalidPasswordException(message);
      case 'forbidden':
        return ForbiddenException(message);
      case 'insufficient_scope':
        return InsufficientScopeException(message);
      case 'not_found':
        return NotFoundException(message);
      case 'conflict':
        return ConflictException(message);
      case 'network':
        return NetworkException(message);
    }
    return PreludeSessionGenericException(code: e.code, message: message);
  }
}

class BadRequestException extends PreludeSessionException {
  const BadRequestException(super.message);
  @override
  String get code => 'bad_request';
}

class UnauthorizedException extends PreludeSessionException {
  const UnauthorizedException(super.message);
  @override
  String get code => 'unauthorized';
}

class RateLimitedException extends PreludeSessionException {
  const RateLimitedException(super.message);
  @override
  String get code => 'rate_limited';
}

class InternalServerErrorException extends PreludeSessionException {
  const InternalServerErrorException(super.message);
  @override
  String get code => 'internal_server_error';
}

class MissingChallengeTokenException extends PreludeSessionException {
  const MissingChallengeTokenException(super.message);
  @override
  String get code => 'missing_challenge_token';
}

class InvalidChallengeTokenException extends PreludeSessionException {
  const InvalidChallengeTokenException(super.message);
  @override
  String get code => 'invalid_challenge_token';
}

/// Step-up challenge token exceeded its TTL. Recover via
/// [PreludeSessionClient.requestStepUp].
class ExpiredChallengeTokenException extends PreludeSessionException {
  const ExpiredChallengeTokenException(super.message);
  @override
  String get code => 'expired_challenge_token';
}

/// Bearer token was already redeemed. Same recovery path as
/// [ExpiredChallengeTokenException]: start a fresh challenge.
class TokenReusedException extends PreludeSessionException {
  const TokenReusedException(super.message);
  @override
  String get code => 'token_reused';
}

/// OTP code submitted during login was wrong or expired. Distinct
/// from [UnauthorizedException]: retry the code, don't re-login.
class InvalidOTPCodeException extends PreludeSessionException {
  const InvalidOTPCodeException(super.message);
  @override
  String get code => 'invalid_otp_code';
}

class RefreshFailedException extends PreludeSessionException {
  const RefreshFailedException(super.message);
  @override
  String get code => 'refresh_failed';
}

class TimeoutException extends PreludeSessionException {
  const TimeoutException() : super('Request timed out');
  @override
  String get code => 'timeout';
}

class InvalidConfigurationException extends PreludeSessionException {
  const InvalidConfigurationException(super.message);
  @override
  String get code => 'invalid_configuration';
}

/// Password rejected by the server's policy. Distinct from
/// [UnauthorizedException] ("wrong password").
class InvalidPasswordException extends PreludeSessionException {
  const InvalidPasswordException(super.message);
  @override
  String get code => 'invalid_password';
}

/// Caller is authenticated but policy denies this action.
class ForbiddenException extends PreludeSessionException {
  const ForbiddenException(super.message);
  @override
  String get code => 'forbidden';
}

/// Access token lacks a scope the endpoint requires. Recover via
/// [PreludeSessionClient.requestStepUp].
class InsufficientScopeException extends PreludeSessionException {
  const InsufficientScopeException(super.message);
  @override
  String get code => 'insufficient_scope';
}

/// Server returned 404 / not_found for the requested resource
/// (e.g. revoking a session id that no longer exists).
class NotFoundException extends PreludeSessionException {
  const NotFoundException(super.message);
  @override
  String get code => 'not_found';
}

/// Server returned 409 / conflict (e.g. an identifier the caller
/// is trying to claim is already taken).
class ConflictException extends PreludeSessionException {
  const ConflictException(super.message);
  @override
  String get code => 'conflict';
}

/// Transport / TLS / DNS failure.
class NetworkException extends PreludeSessionException {
  const NetworkException(super.message);
  @override
  String get code => 'network';
}

/// Catch-all for codes the SDK doesn't yet model. Lets the bridge
/// stay forward-compatible with new server-side error codes
/// without a Flutter SDK release.
class PreludeSessionGenericException extends PreludeSessionException {
  const PreludeSessionGenericException({
    required String code,
    required String message,
  }) : _code = code,
       super(message);

  final String _code;

  @override
  String get code => _code;
}
