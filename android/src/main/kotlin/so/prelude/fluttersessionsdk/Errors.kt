package so.prelude.fluttersessionsdk

import so.prelude.android.session.PreludeSessionError

/** Wire-shape payload for `MethodChannel.Result.error`. */
internal data class FlutterErrorPayload(val code: String, val message: String)

/**
 * Local exception type for argument / config decode failures. Kept
 * distinct from [PreludeSessionError] so the error mapper can route
 * decode failures to a stable `bad_request` code without reaching
 * for the SDK's error hierarchy.
 */
internal class DecodeException(message: String) : Exception(message)

internal fun decodeError(message: String): Throwable = DecodeException(message)

internal fun missingArg(method: String, name: String): Throwable =
    DecodeException("$method: missing required arg `$name`")

internal fun mapError(error: Throwable): FlutterErrorPayload =
    when (error) {
        is PreludeSessionError -> mapSessionError(error)
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
 * Match Dart's `PreludeSessionException.fromPlatformException` switch
 * arm-for-arm so the typed Dart exceptions hydrate correctly.
 * `Generic(code, message)` round-trips its server code as the
 * FlutterError code so unknown codes still surface to consumers.
 */
private fun mapSessionError(error: PreludeSessionError): FlutterErrorPayload =
    when (error) {
        is PreludeSessionError.BadRequest ->
            FlutterErrorPayload("bad_request", error.message.orEmpty())
        is PreludeSessionError.Unauthorized ->
            FlutterErrorPayload("unauthorized", error.message.orEmpty())
        is PreludeSessionError.RateLimited ->
            FlutterErrorPayload("rate_limited", error.message.orEmpty())
        is PreludeSessionError.InternalServerError ->
            FlutterErrorPayload("internal_server_error", error.message.orEmpty())
        is PreludeSessionError.MissingChallengeToken ->
            FlutterErrorPayload("missing_challenge_token", error.message.orEmpty())
        is PreludeSessionError.InvalidChallengeToken ->
            FlutterErrorPayload("invalid_challenge_token", error.message.orEmpty())
        is PreludeSessionError.InvalidOTPCode ->
            FlutterErrorPayload("invalid_otp_code", error.message.orEmpty())
        is PreludeSessionError.RefreshFailed ->
            FlutterErrorPayload("refresh_failed", error.message.orEmpty())
        is PreludeSessionError.Timeout ->
            FlutterErrorPayload("timeout", "Request timed out")
        is PreludeSessionError.InvalidConfiguration ->
            FlutterErrorPayload("invalid_configuration", error.message.orEmpty())
        is PreludeSessionError.InvalidPassword ->
            FlutterErrorPayload("invalid_password", error.message.orEmpty())
        is PreludeSessionError.Forbidden ->
            FlutterErrorPayload("forbidden", error.message.orEmpty())
        is PreludeSessionError.InsufficientScope ->
            FlutterErrorPayload("insufficient_scope", error.message.orEmpty())
        is PreludeSessionError.Network ->
            FlutterErrorPayload("network", error.cause?.message ?: error.message.orEmpty())
        // Dart doesn't model these natively; surface through the
        // generic catch-all with a stable code so consumers can
        // still branch on them when needed.
        is PreludeSessionError.CryptoFailure ->
            FlutterErrorPayload("crypto_failure", error.cause?.message ?: error.message.orEmpty())
        is PreludeSessionError.SignalsDispatchFailed ->
            FlutterErrorPayload(
                "signals_dispatch_failed",
                error.cause?.message ?: error.message.orEmpty(),
            )
        is PreludeSessionError.Generic ->
            FlutterErrorPayload(error.code, error.displayMessage)
    }
