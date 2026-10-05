package so.prelude.flutterauthsdk

import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.MethodCall
import so.prelude.android.auth.FinalizeOAuthLoginResult
import so.prelude.android.auth.PreludeListSessionsOptions
import so.prelude.android.auth.PreludeRevokeTarget
import so.prelude.android.auth.PreludeAuthClient
import so.prelude.android.auth.PreludeAuthError
import so.prelude.android.auth.PreludeStepUpChallenge
import so.prelude.android.auth.RedactedString
import so.prelude.android.auth.changePassword
import so.prelude.android.auth.canChangePassword
import so.prelude.android.auth.checkOAuthEmailOTP
import so.prelude.android.auth.checkOTP
import so.prelude.android.auth.continueStepUpWithPasskey
import so.prelude.android.auth.deletePasskey
import so.prelude.android.auth.finalizeOAuthLogin
import so.prelude.android.auth.getPasswordCompliancy
import so.prelude.android.auth.initiateOAuthLogin
import so.prelude.android.auth.listPasskeys
import so.prelude.android.auth.listSessions
import so.prelude.android.auth.loginWithPasskey
import so.prelude.android.auth.loginWithPassword
import so.prelude.android.auth.migrate
import so.prelude.android.auth.logout
import so.prelude.android.auth.registerPasskey
import so.prelude.android.auth.renamePasskey
import so.prelude.android.auth.requestStepUp
import so.prelude.android.auth.resendOTP
import so.prelude.android.auth.revokeSessions
import so.prelude.android.auth.sendStepUpOTP
import so.prelude.android.auth.social.loginWithOAuth
import so.prelude.android.auth.startOTPLogin
import so.prelude.android.auth.submitStepUpOTP

/** Methods routed through [dispatch]. Listed up front so unknown
 *  method names short-circuit with `notImplemented` before the
 *  plugin provisions a native client. */
internal val ASYNC_METHODS: Set<String> = setOf(
    "startOTPLogin", "resendOTP", "checkOTP",
    "loginWithPassword", "migrate", "passwordCompliancy", "changePassword", "canChangePassword",
    "loginWithOAuth", "initiateOAuthLogin", "finalizeOAuthLogin", "checkOAuthEmailOTP",
    "refresh", "logout", "invalidateSession",
    "listSessions", "revokeSessions",
    "requestStepUp", "sendStepUpOTP", "submitStepUpOTP",
    "getActiveStepUp", "continueStepUpWithPasskey",
    "registerPasskey", "loginWithPasskey",
    "listPasskeys", "renamePasskey", "deletePasskey",
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
    context: Context,
    activity: () -> Activity?,
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
    "canChangePassword" -> client.canChangePassword()

    // Migration -----------------------------------------------
    "migrate" ->
        Codec.encodeUser(client.migrate(decodeMigrateOptions(args["options"])))

    // Social / OAuth login ------------------------------------
    "loginWithOAuth" -> encodeOAuthResult(
        client.loginWithOAuth(context, decodeOAuthLoginOptions(args["options"])),
        handle,
        registry,
    )
    "initiateOAuthLogin" -> {
        val loginContext = client.initiateOAuthLogin(decodeInitiateOAuthLoginOptions(args["options"]))
        registry.cacheOAuthContext(handle, loginContext)
        loginContext.authorizationUrl.toString()
    }
    "finalizeOAuthLogin" -> {
        val token = args["challengeToken"] as? String
            ?: throw missingArg("finalizeOAuthLogin", "challengeToken")
        val loginContext = registry.lookupOAuthContext(handle)
        val result = client.finalizeOAuthLogin(loginContext, token)
        registry.evictOAuthContext(handle)
        encodeOAuthResult(result, handle, registry)
    }
    "checkOAuthEmailOTP" -> handleCheckOAuthEmailOTP(args, handle, client, registry)

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

    "continueStepUpWithPasskey" ->
        handleContinueStepUpWithPasskey(args, handle, client, registry, activity)

    // Passkey -------------------------------------------------
    "registerPasskey" -> Codec.encodeRegistration(
        client.registerPasskey(
            requireActivity(activity, call.method),
            decodeRegisterPasskeyOptions(args["options"]),
        ),
    )
    "loginWithPasskey" -> Codec.encodeUser(
        client.loginWithPasskey(requireActivity(activity, call.method)),
    )
    "listPasskeys" -> client.listPasskeys().map { Codec.encodeCredential(it) }
    "renamePasskey" -> {
        val credentialId = args["credentialID"] as? String
        val nickname = args["nickname"] as? String
        if (credentialId == null || nickname == null) {
            throw missingArg("renamePasskey", "credentialID/nickname")
        }
        client.renamePasskey(credentialId, nickname)
        null
    }
    "deletePasskey" -> {
        val credentialId = args["credentialID"] as? String
            ?: throw missingArg("deletePasskey", "credentialID")
        client.deletePasskey(credentialId)
        null
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

/**
 * The Credential Manager presents a system sheet, so it needs the
 * hosting Activity — the application context the rest of the bridge
 * uses can't launch UI. Resolved through a supplier, and re-read here
 * rather than snapshotted at dispatch entry, so a call that overlaps
 * an attach doesn't fail on a value read moments too early.
 */
private fun requireActivity(activity: () -> Activity?, method: String): Activity {
    val host = activity()
    if (host == null || host.isFinishing || host.isDestroyed) {
        throw PreludeAuthError.InvalidConfiguration(
            "$method needs a foreground Activity; none is attached to the Flutter engine.",
        )
    }
    return host
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
    return advanceStepUp(
        handle,
        registry,
        challenge,
        // A wrong code keeps the challenge usable up to the server's
        // bucket limit. Any other error kills it.
        keepsChallenge = { it is PreludeAuthError.InvalidOTPCode },
    ) { client.submitStepUpOTP(challenge, code) }
}

private suspend fun handleContinueStepUpWithPasskey(
    args: Map<*, *>,
    handle: String,
    client: PreludeAuthClient,
    registry: ClientRegistry,
    activity: () -> Activity?,
): Any? {
    val challengeId = args["challengeID"] as? String
        ?: throw missingArg("continueStepUpWithPasskey", "challengeID")
    val host = requireActivity(activity, "continueStepUpWithPasskey")
    val challenge = registry.lookupChallenge(handle, challengeId)
    return advanceStepUp(
        handle,
        registry,
        challenge,
        // Unlike an OTP submit, most passkey failures happen before the
        // request is sent — a dismissed sheet, an OS without platform
        // WebAuthn, no usable credential — and leave the challenge good
        // for a fallback step. So retire it only when the error says the
        // token itself is gone.
        keepsChallenge = {
            it !is PreludeAuthError.InvalidChallengeToken &&
                it !is PreludeAuthError.ExpiredChallengeToken &&
                it !is PreludeAuthError.TokenReused
        },
    ) { client.continueStepUpWithPasskey(host, challenge) }
}

/**
 * Run one step-up [step] against [challenge] and reconcile the cache
 * with its outcome: swap in the challenge the step returns, or drop
 * the entry once the flow completes. On failure [keepsChallenge]
 * decides whether the challenge survives for another attempt.
 */
private suspend fun advanceStepUp(
    handle: String,
    registry: ClientRegistry,
    challenge: PreludeStepUpChallenge,
    keepsChallenge: (PreludeAuthError) -> Boolean,
    step: suspend () -> PreludeStepUpChallenge?,
): Map<String, Any?>? {
    val next = try {
        step()
    } catch (e: PreludeAuthError) {
        if (!keepsChallenge(e)) registry.evictChallenge(handle, challenge.challengeId)
        throw e
    }
    if (next == null) {
        // Flow completed: post-completion refresh has already minted
        // the scoped access token.
        registry.evictChallenge(handle, challenge.challengeId)
        return null
    }
    // Insert before evicting so a concurrent reader observing under
    // the new ID never sees an empty slot during a multi-step
    // transition.
    registry.cacheChallenge(handle, next)
    if (next.challengeId != challenge.challengeId) {
        registry.evictChallenge(handle, challenge.challengeId)
    }
    return Codec.encodeChallenge(next)
}

/**
 * Encode an OAuth outcome for the channel, caching the email-link
 * challenge so only its generated key crosses the bridge. Shared by
 * the `loginWithOAuth` and `finalizeOAuthLogin` arms.
 */
private fun encodeOAuthResult(
    result: FinalizeOAuthLoginResult,
    handle: String,
    registry: ClientRegistry,
): Map<String, Any?> =
    when (result) {
        is FinalizeOAuthLoginResult.LoggedIn ->
            mapOf("kind" to "logged_in", "user" to Codec.encodeUser(result.user))
        is FinalizeOAuthLoginResult.OtpRequired -> {
            val challengeId = registry.cacheOAuthEmailChallenge(handle, result.challenge)
            mapOf(
                "kind" to "otp_required",
                "challengeID" to challengeId,
                "email" to result.email,
            )
        }
    }

private suspend fun handleCheckOAuthEmailOTP(
    args: Map<*, *>,
    handle: String,
    client: PreludeAuthClient,
    registry: ClientRegistry,
): Any? {
    val challengeId = args["challengeID"] as? String
    val code = args["code"] as? String
    if (challengeId == null || code == null) {
        throw missingArg("checkOAuthEmailOTP", "challengeID/code")
    }
    val challenge = registry.lookupOAuthEmailChallenge(handle, challengeId)
    return try {
        val user = client.checkOAuthEmailOTP(code, challenge)
        registry.evictOAuthEmailChallenge(handle, challengeId)
        Codec.encodeUser(user)
    } catch (e: PreludeAuthError) {
        // A wrong code keeps the challenge usable up to the server's
        // bucket limit; any other error retires it.
        if (e !is PreludeAuthError.InvalidOTPCode) {
            registry.evictOAuthEmailChallenge(handle, challengeId)
        }
        throw e
    }
}
