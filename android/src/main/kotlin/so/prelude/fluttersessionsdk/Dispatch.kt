package so.prelude.fluttersessionsdk

import io.flutter.plugin.common.MethodCall
import so.prelude.android.session.PreludeSessionClient
import so.prelude.android.session.PreludeSessionError
import so.prelude.android.session.RedactedString
import so.prelude.android.session.changePassword
import so.prelude.android.session.checkOTP
import so.prelude.android.session.getPasswordCompliancy
import so.prelude.android.session.loginWithPassword
import so.prelude.android.session.logout
import so.prelude.android.session.requestStepUp
import so.prelude.android.session.retryOTP
import so.prelude.android.session.startOTPLogin
import so.prelude.android.session.submitStepUpOTP

/** Methods routed through [dispatch]. Listed up front so unknown
 *  method names short-circuit with `notImplemented` before the
 *  plugin provisions a native client. */
internal val ASYNC_METHODS: Set<String> = setOf(
    "startOTPLogin", "resendOTP", "checkOTP",
    "loginWithPassword", "passwordCompliancy", "changePassword",
    "refresh", "logout", "invalidateSession",
    "requestStepUp", "submitStepUpOTP",
    "getProfile", "getSessionID",
    "getAccessToken", "getAccessTokenExpiresAt",
)

/**
 * Route a single call to the matching `PreludeSessionClient`
 * suspend function, encode the result back to a Dart-friendly map,
 * and surface any throw as a `PreludeSessionError` for the outer
 * error mapper to translate.
 */
internal suspend fun dispatch(
    call: MethodCall,
    args: Map<*, *>,
    handle: String,
    client: PreludeSessionClient,
    registry: ClientRegistry,
): Any? = when (call.method) {
    // OTP -----------------------------------------------------
    "startOTPLogin" -> {
        client.startOTPLogin(decodeStartOTPLoginOptions(args["options"]))
        null
    }
    "resendOTP" -> {
        client.retryOTP()
        null
    }
    "checkOTP" -> {
        val code = args["code"] as? String ?: throw missingArg("checkOTP", "code")
        Codec.encodeUser(client.checkOTP(code))
    }

    // Password ------------------------------------------------
    "loginWithPassword" -> {
        val options = decodeLoginWithPasswordOptions(args["options"])
        Codec.encodeUser(client.loginWithPassword(options))
    }
    "passwordCompliancy" ->
        // `validatePassword` is intentionally absent — Dart classifies
        // locally against the cached compliancy.
        Codec.encodeCompliancy(client.getPasswordCompliancy())
    "changePassword" -> {
        val newPassword = args["newPassword"] as? String
            ?: throw missingArg("changePassword", "newPassword")
        client.changePassword(RedactedString(newPassword))
        null
    }

    // Refresh / logout / invalidate ---------------------------
    "refresh" -> Codec.encodeUser(client.refresh())
    "logout" -> {
        client.logout()
        null
    }
    "invalidateSession" -> {
        // Marks the cached access token stale without removing it.
        // No network call; the refresh token is untouched.
        client.invalidateCache()
        null
    }

    // Step-up -------------------------------------------------
    "requestStepUp" -> {
        val scopeArg = args["scope"] as? String ?: throw missingArg("requestStepUp", "scope")
        val challenge = client.requestStepUp(scopeArg)
        registry.cacheChallenge(handle, challenge)
        Codec.encodeChallenge(challenge)
    }
    "submitStepUpOTP" -> handleSubmitStepUpOTP(args, handle, client, registry)

    // Cached readers ------------------------------------------
    "getProfile" -> client.getProfile()?.let { Codec.encodeProfile(it) }
    "getSessionID" -> client.getSessionId()
    "getAccessToken" -> client.getAccessToken()
    "getAccessTokenExpiresAt" -> client.getAccessTokenExpiresAt()?.epochSecond

    // Unreachable: filtered against [ASYNC_METHODS] in the plugin.
    // If you add a new async method, also add it to the allowlist
    // *and* a branch here.
    else -> throw decodeError("dispatch: unhandled method `${call.method}`")
}

private suspend fun handleSubmitStepUpOTP(
    args: Map<*, *>,
    handle: String,
    client: PreludeSessionClient,
    registry: ClientRegistry,
): Any? {
    val challengeId = args["challengeID"] as? String
    val code = args["code"] as? String
    if (challengeId == null || code == null) {
        throw missingArg("submitStepUpOTP", "challengeID/code")
    }
    val challenge = registry.lookupChallenge(handle, challengeId)
    return try {
        val next = client.submitStepUpOTP(challenge, code)
        if (next != null) {
            // Insert before evicting so a concurrent reader observing
            // under the new ID never sees an empty slot during a
            // multi-step transition.
            registry.cacheChallenge(handle, next)
            if (next.challengeId != challenge.challengeId) {
                registry.evictChallenge(handle, challenge.challengeId)
            }
            Codec.encodeChallenge(next)
        } else {
            // Flow completed: post-completion refresh has already
            // minted the scoped access token.
            registry.evictChallenge(handle, challenge.challengeId)
            null
        }
    } catch (e: PreludeSessionError) {
        // `InvalidOTPCode` keeps the challenge usable up to the
        // server's bucket limit. Any other error kills it.
        if (e !is PreludeSessionError.InvalidOTPCode) {
            registry.evictChallenge(handle, challenge.challengeId)
        }
        throw e
    }
}
