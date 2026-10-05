import 'package:flutter/services.dart';

/// Base type for every error thrown by [PreludeAuthClient].
///
/// A helper [PreludeAuthException.fromPlatformException] decodes
/// the structured `code` / `message` / `details` produced by the
/// native plugin into the matching Dart subtype, so consumers can
/// `try/catch` against specific cases (`InvalidOTPCodeException`,
/// `InsufficientScopeException`, …) instead of inspecting raw
/// channel error codes.
sealed class PreludeAuthException implements Exception {
  const PreludeAuthException(this.message);

  /// Human-readable message.
  final String message;

  /// Stable code identifying the case. Used by the bridge for
  /// round-tripping and for consumer matching when needed.
  String get code;

  @override
  String toString() => '$runtimeType($code): $message';

  /// Decode a [PlatformException] thrown by the method channel
  /// into the matching typed subtype. Falls back to
  /// [PreludeAuthGenericException] when the code isn't
  /// recognised — keeping forward compatibility cheap.
  static PreludeAuthException fromPlatformException(PlatformException e) {
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
      case 'no_login_config':
        return NoLoginConfigException(message);
      case 'invalid_password':
        return InvalidPasswordException(message);
      case 'password_not_set':
        return PasswordNotSetException(message);
      case 'forbidden':
        return ForbiddenException(message);
      case 'insufficient_scope':
        return InsufficientScopeException(message);
      case 'not_found':
        return NotFoundException(message);
      case 'conflict':
        return ConflictException(message);
      case 'saml_login_required':
        return SAMLLoginRequiredException(message);
      case 'passkey_not_configured':
        return PasskeyNotConfiguredException(message);
      case 'passkey_registration_failed':
        return PasskeyRegistrationFailedException(message);
      case 'passkey_step_unavailable':
        return PasskeyStepUnavailableException(message);
      case 'passkey_not_supported':
        return PasskeyNotSupportedException(message);
      case 'passkey_already_registered':
        return PasskeyAlreadyRegisteredException(message);
      case 'network':
        return NetworkException(message);
      case 'cancelled':
        return const CancelledException();
    }
    return PreludeAuthGenericException(code: e.code, message: message);
  }
}

class BadRequestException extends PreludeAuthException {
  const BadRequestException(super.message);
  @override
  String get code => 'bad_request';
}

class UnauthorizedException extends PreludeAuthException {
  const UnauthorizedException(super.message);
  @override
  String get code => 'unauthorized';
}

class RateLimitedException extends PreludeAuthException {
  const RateLimitedException(super.message);
  @override
  String get code => 'rate_limited';
}

class InternalServerErrorException extends PreludeAuthException {
  const InternalServerErrorException(super.message);
  @override
  String get code => 'internal_server_error';
}

class MissingChallengeTokenException extends PreludeAuthException {
  const MissingChallengeTokenException(super.message);
  @override
  String get code => 'missing_challenge_token';
}

class InvalidChallengeTokenException extends PreludeAuthException {
  const InvalidChallengeTokenException(super.message);
  @override
  String get code => 'invalid_challenge_token';
}

/// Step-up challenge token exceeded its TTL. Recover via
/// [PreludeAuthClient.requestStepUp].
class ExpiredChallengeTokenException extends PreludeAuthException {
  const ExpiredChallengeTokenException(super.message);
  @override
  String get code => 'expired_challenge_token';
}

/// Bearer token was already redeemed. Same recovery path as
/// [ExpiredChallengeTokenException]: start a fresh challenge.
class TokenReusedException extends PreludeAuthException {
  const TokenReusedException(super.message);
  @override
  String get code => 'token_reused';
}

/// OTP code submitted during login was wrong or expired. Distinct
/// from [UnauthorizedException]: retry the code, don't re-login.
class InvalidOTPCodeException extends PreludeAuthException {
  const InvalidOTPCodeException(super.message);
  @override
  String get code => 'invalid_otp_code';
}

class RefreshFailedException extends PreludeAuthException {
  const RefreshFailedException(super.message);
  @override
  String get code => 'refresh_failed';
}

class TimeoutException extends PreludeAuthException {
  const TimeoutException() : super('Request timed out');
  @override
  String get code => 'timeout';
}

class InvalidConfigurationException extends PreludeAuthException {
  const InvalidConfigurationException(super.message);
  @override
  String get code => 'invalid_configuration';
}

/// The app has no login configuration accepting this identifier's
/// channel. Create one via the Auth Management API.
class NoLoginConfigException extends PreludeAuthException {
  const NoLoginConfigException(super.message);
  @override
  String get code => 'no_login_config';
}

/// Password rejected by the server's policy. Distinct from
/// [UnauthorizedException] ("wrong password").
class InvalidPasswordException extends PreludeAuthException {
  const InvalidPasswordException(super.message);
  @override
  String get code => 'invalid_password';
}

/// Returned by `/login/email/password` when the user exists but has no
/// password credential stored. Distinct from [UnauthorizedException]
/// ("wrong password"); recover via a password reset/set flow instead
/// of retrying the password.
class PasswordNotSetException extends PreludeAuthException {
  const PasswordNotSetException(super.message);
  @override
  String get code => 'password_not_set';
}

/// Caller is authenticated but policy denies this action.
class ForbiddenException extends PreludeAuthException {
  const ForbiddenException(super.message);
  @override
  String get code => 'forbidden';
}

/// Access token lacks a scope the endpoint requires. Recover via
/// [PreludeAuthClient.requestStepUp].
class InsufficientScopeException extends PreludeAuthException {
  const InsufficientScopeException(super.message);
  @override
  String get code => 'insufficient_scope';
}

/// Server returned 404 / not_found for the requested resource
/// (e.g. revoking a session id that no longer exists).
class NotFoundException extends PreludeAuthException {
  const NotFoundException(super.message);
  @override
  String get code => 'not_found';
}

/// Server returned 409 / conflict (e.g. an identifier the caller
/// is trying to claim is already taken).
class ConflictException extends PreludeAuthException {
  const ConflictException(super.message);
  @override
  String get code => 'conflict';
}

/// OTP or other login method refused because the identifier's email
/// domain is enforced to use SAML SSO. Recover by restarting the
/// flow via the SAML initiate endpoint.
class SAMLLoginRequiredException extends PreludeAuthException {
  const SAMLLoginRequiredException(super.message);
  @override
  String get code => 'saml_login_required';
}

/// App has no PasskeyConfig set (Relying Party identity is missing).
/// Route the user to a different MFA factor.
class PasskeyNotConfiguredException extends PreludeAuthException {
  const PasskeyNotConfiguredException(super.message);
  @override
  String get code => 'passkey_not_configured';
}

/// Server rejected the attestation from the registration ceremony —
/// bad challenge, bad origin, or malformed authenticator response.
class PasskeyRegistrationFailedException extends PreludeAuthException {
  const PasskeyRegistrationFailedException(super.message);
  @override
  String get code => 'passkey_registration_failed';
}

/// verify_passkey step cannot be driven — no credentials, assertion
/// failed, or no PasskeyConfig. Fall back to a different step.
class PasskeyStepUnavailableException extends PreludeAuthException {
  const PasskeyStepUnavailableException(super.message);
  @override
  String get code => 'passkey_step_unavailable';
}

/// This device or OS version can't drive a passkey ceremony (iOS
/// below 16, Android below API 28, or the platform credential
/// provider is unavailable). Thrown locally — the server is never
/// contacted. Offer another factor.
class PasskeyNotSupportedException extends PreludeAuthException {
  const PasskeyNotSupportedException(super.message);
  @override
  String get code => 'passkey_not_supported';
}

/// The authenticator already holds a passkey for this account, so it
/// refused to create another. Nothing to recover from — the existing
/// credential still works for login.
class PasskeyAlreadyRegisteredException extends PreludeAuthException {
  const PasskeyAlreadyRegisteredException(super.message);
  @override
  String get code => 'passkey_already_registered';
}

/// Transport / TLS / DNS failure.
class NetworkException extends PreludeAuthException {
  const NetworkException(super.message);
  @override
  String get code => 'network';
}

/// The person dismissed the login UI before completing it. Not a
/// failure — typically swallowed by the caller.
class CancelledException extends PreludeAuthException {
  const CancelledException() : super('Cancelled');
  @override
  String get code => 'cancelled';
}

/// Catch-all for codes the SDK doesn't yet model. Lets the bridge
/// stay forward-compatible with new server-side error codes
/// without a Flutter SDK release.
class PreludeAuthGenericException extends PreludeAuthException {
  const PreludeAuthGenericException({
    required String code,
    required String message,
  }) : _code = code,
       super(message);

  final String _code;

  @override
  String get code => _code;
}
