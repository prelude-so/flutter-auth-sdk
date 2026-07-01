package so.prelude.flutterauthsdk

import so.prelude.android.auth.PreludeAuthError

/** Wire-shape payload for `MethodChannel.Result.error`. */
internal data class FlutterErrorPayload(val code: String, val message: String)

/**
 * Local exception type for argument / config decode failures. Kept
 * distinct from [PreludeAuthError] so the error mapper can route
 * decode failures to a stable `bad_request` code without reaching
 * for the SDK's error hierarchy.
 */
internal class DecodeException(message: String) : Exception(message)

internal fun decodeError(message: String): Throwable = DecodeException(message)

internal fun missingArg(method: String, name: String): Throwable =
    DecodeException("$method: missing required arg `$name`")

internal fun mapError(error: Throwable): FlutterErrorPayload =
    when (error) {
        is PreludeAuthError -> mapSessionError(error)
        is DecodeException -> FlutterErrorPayload(
            code = "bad_request",
            message = error.message ?: "bad_request",
        )
        else -> FlutterErrorPayload(
            code = "generic",
            message = error.toString(),
        )
    }

/**
 * Match Dart's `PreludeAuthException.fromPlatformException` switch
 * arm-for-arm so the typed Dart exceptions hydrate correctly.
 * `Generic(code, message)` round-trips its server code as the
 * FlutterError code so unknown codes still surface to consumers.
 */
private fun mapSessionError(error: PreludeAuthError): FlutterErrorPayload =
    when (error) {
        is PreludeAuthError.BadRequest ->
            FlutterErrorPayload("bad_request", error.message.orEmpty())
        is PreludeAuthError.Unauthorized ->
            FlutterErrorPayload("unauthorized", error.message.orEmpty())
        is PreludeAuthError.RateLimited ->
            FlutterErrorPayload("rate_limited", error.message.orEmpty())
        is PreludeAuthError.InternalServerError ->
            FlutterErrorPayload("internal_server_error", error.message.orEmpty())
        is PreludeAuthError.MissingChallengeToken ->
            FlutterErrorPayload("missing_challenge_token", error.message.orEmpty())
        is PreludeAuthError.InvalidChallengeToken ->
            FlutterErrorPayload("invalid_challenge_token", error.message.orEmpty())
        is PreludeAuthError.ExpiredChallengeToken ->
            FlutterErrorPayload("expired_challenge_token", error.message.orEmpty())
        is PreludeAuthError.TokenReused ->
            FlutterErrorPayload("token_reused", error.message.orEmpty())
        is PreludeAuthError.InvalidOTPCode ->
            FlutterErrorPayload("invalid_otp_code", error.message.orEmpty())
        is PreludeAuthError.RefreshFailed ->
            FlutterErrorPayload("refresh_failed", error.message.orEmpty())
        is PreludeAuthError.Timeout ->
            FlutterErrorPayload("timeout", "Request timed out")
        is PreludeAuthError.Cancelled ->
            FlutterErrorPayload("cancelled", "Request cancelled")
        is PreludeAuthError.InvalidConfiguration ->
            FlutterErrorPayload("invalid_configuration", error.message.orEmpty())
        is PreludeAuthError.InvalidPassword ->
            FlutterErrorPayload("invalid_password", error.message.orEmpty())
        is PreludeAuthError.Forbidden ->
            FlutterErrorPayload("forbidden", error.message.orEmpty())
        is PreludeAuthError.InsufficientScope ->
            FlutterErrorPayload("insufficient_scope", error.message.orEmpty())
        is PreludeAuthError.NotFound ->
            FlutterErrorPayload("not_found", error.message.orEmpty())
        is PreludeAuthError.SamlLoginRequired ->
            FlutterErrorPayload("saml_login_required", error.message.orEmpty())
        // Dart doesn't model the passkey errors natively; surface them
        // through the generic catch-all with stable codes so consumers
        // can still branch on them.
        is PreludeAuthError.PasskeyNotConfigured ->
            FlutterErrorPayload("passkey_not_configured", error.message.orEmpty())
        is PreludeAuthError.PasskeyRegistrationFailed ->
            FlutterErrorPayload("passkey_registration_failed", error.message.orEmpty())
        is PreludeAuthError.PasskeyStepUnavailable ->
            FlutterErrorPayload("passkey_step_unavailable", error.message.orEmpty())
        is PreludeAuthError.Conflict ->
            FlutterErrorPayload("conflict", error.message.orEmpty())
        is PreludeAuthError.Network ->
            FlutterErrorPayload("network", error.cause?.message ?: error.message.orEmpty())
        // Dart doesn't model this natively; surface through the
        // generic catch-all with a stable code so consumers can
        // still branch on it when needed.
        is PreludeAuthError.CryptoFailure ->
            FlutterErrorPayload("crypto_failure", error.cause?.message ?: error.message.orEmpty())
        is PreludeAuthError.Generic ->
            FlutterErrorPayload(error.code, error.displayMessage)
    }
