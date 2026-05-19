package so.prelude.flutterauthsdk

import io.flutter.plugin.common.MethodCall
import so.prelude.android.auth.PreludeListSessionsOptions
import so.prelude.android.auth.PreludeRevokeTarget
import so.prelude.android.auth.PreludeAuthClient
import so.prelude.android.auth.PreludeAuthError
import so.prelude.android.auth.RedactedString
import so.prelude.android.auth.changePassword
import so.prelude.android.auth.checkOTP
import so.prelude.android.auth.getPasswordCompliancy
import so.prelude.android.auth.listSessions
import so.prelude.android.auth.loginWithPassword
import so.prelude.android.auth.logout
import so.prelude.android.auth.requestStepUp
import so.prelude.android.auth.resendOTP
import so.prelude.android.auth.revokeSessions
import so.prelude.android.auth.sendStepUpOTP
import so.prelude.android.auth.startOTPLogin
import so.prelude.android.auth.submitStepUpOTP

/** Methods routed through [dispatch]. Listed up front so unknown
 *  method names short-circuit with `notImplemented` before the
 *  plugin provisions a native client. */
internal val ASYNC_METHODS: Set<String> = setOf(
    "startOTPLogin", "resendOTP", "checkOTP",
    "loginWithPassword", "passwordCompliancy", "changePassword",
    "refresh", "logout", "invalidateSession",
    "listSessions", "revokeSessions",
    "requestStepUp", "sendStepUpOTP", "submitStepUpOTP",
    "getActiveStepUp",
    "getProfile", "getSessionID",
    "getAccessToken", "getAccessTokenExpiresAt",
)

/**
 * Route a single call to the matching `PreludeAuthClient`
 * suspend function, encode the result back to a Dart-friendly map,
 * and surface any throw as a `PreludeAuthError` for the outer
 * error mapper to translate.
 */
internal suspend fun dispatch(
    call: MethodCall,
    args: Map<*, *>,
    handle: String,
    client: PreludeAuthClient,
    registry: ClientRegistry,
): Any? = when (call.method) {
    // OTP -----------------------------------------------------
    "startOTPLogin" -> {
        client.startOTPLogin(decodeStartOTPLoginOptions(args["options"]))
        null
    }
    "resendOTP" -> {
        client.resendOTP()
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

    // Manage sessions -----------------------------------------
    "listSessions" -> Codec.encodeListSessions(
        client.listSessions(decodeListSessionsOptions(args["options"])),
    )
    "revokeSessions" -> {
        client.revokeSessions(decodeRevokeTarget(args["target"]))
        null
    }

    // Step-up -------------------------------------------------
    "requestStepUp" -> {
        val scopeArg = args["scope"] as? String ?: throw missingArg("requestStepUp", "scope")
        val metadata = decodeMetadata(args["metadata"])
        val challenge = client.requestStepUp(scopeArg, metadata)
        registry.cacheChallenge(handle, challenge)
        Codec.encodeChallenge(challenge)
    }
    "sendStepUpOTP" -> handleSendStepUpOTP(args, handle, client, registry)
    "submitStepUpOTP" -> handleSubmitStepUpOTP(args, handle, client, registry)
    "getActiveStepUp" -> client.activeStepUp?.let {
        // Mirror into the per-handle cache so a follow-up
        // `submitStepUpOTP` resolves the bearer challenge token
        // without the caller needing to hold the handle locally.
        registry.cacheChallenge(handle, it)
        Codec.encodeChallenge(it)
    }

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

private suspend fun handleSendStepUpOTP(
    args: Map<*, *>,
    handle: String,
    client: PreludeAuthClient,
    registry: ClientRegistry,
): Any? {
    val challengeId = args["challengeID"] as? String
        ?: throw missingArg("sendStepUpOTP", "challengeID")
    val challenge = registry.lookupChallenge(handle, challengeId)
    client.sendStepUpOTP(challenge)
    return null
}

private suspend fun handleSubmitStepUpOTP(
    args: Map<*, *>,
    handle: String,
    client: PreludeAuthClient,
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
    } catch (e: PreludeAuthError) {
        // `InvalidOTPCode` keeps the challenge usable up to the
        // server's bucket limit. Any other error kills it.
        if (e !is PreludeAuthError.InvalidOTPCode) {
            registry.evictChallenge(handle, challenge.challengeId)
        }
        throw e
    }
}
