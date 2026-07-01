package so.prelude.flutterauthsdk

import android.content.Context
import android.content.pm.PackageManager
import so.prelude.android.auth.OAuthEmailChallenge
import so.prelude.android.auth.OAuthLoginContext
import so.prelude.android.auth.PreludeAuthClient
import so.prelude.android.auth.PreludeAuthError
import so.prelude.android.auth.PreludeStepUpChallenge
import so.prelude.android.auth.PreludeStepUpStatus
import java.util.UUID

/**
 * `AndroidManifest.xml` meta-data key the SDK reads for the
 * platform's Prelude signals SDK key. Symmetric with the iOS
 * plugin's `Info.plist` `PreludeSDKKey` lookup.
 */
private const val MANIFEST_SDK_KEY = "so.prelude.sdk_key"

/**
 * Resolve the Prelude signals SDK key for this app.
 *
 * Precedence: Dart-supplied override > manifest meta-data. Empty
 * strings are treated as absent so an unconfigured manifest entry
 * doesn't construct a half-wired dispatcher. Returning `null` is
 * a supported no-op — signals just don't dispatch and `dispatch_id`
 * is omitted from login bodies.
 */
internal fun resolveSignalsSDKKey(context: Context, override: String?): String? {
    if (!override.isNullOrBlank()) return override
    return try {
        val info = context.packageManager.getApplicationInfo(
            context.packageName,
            PackageManager.GET_META_DATA,
        )
        info.metaData?.getString(MANIFEST_SDK_KEY)?.takeIf { it.isNotBlank() }
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }
}

/**
 * Per-handle native client cache plus per-handle in-flight step-up
 * challenges. A single lock covers both: their lifetimes are coupled
 * (disposing a handle should evict both in lockstep) and the wire
 * form sent across the channel relies on the challenge cache to keep
 * the bearer challenge JWT off the bridge.
 */
internal class ClientRegistry {
    private val clients: MutableMap<String, PreludeAuthClient> = mutableMapOf()
    private val challenges: MutableMap<String, MutableMap<String, PreludeStepUpChallenge>> =
        mutableMapOf()

    /**
     * Per-handle in-flight OAuth login context, one slot per handle.
     * Holds the authorize step's PKCE verifier between initiate and
     * finalize so it never crosses the channel; a later initiate
     * supersedes an unredeemed earlier attempt.
     */
    private val oauthContexts: MutableMap<String, OAuthLoginContext> = mutableMapOf()

    /**
     * One cached OAuth email-link challenge plus the id minted for it,
     * so a superseded challenge is rejected rather than silently
     * redeemed against a newer attempt.
     */
    private data class CachedOAuthEmailChallenge(val id: String, val challenge: OAuthEmailChallenge)

    /**
     * Per-handle in-flight OAuth email-link challenge, one slot per
     * handle. The challenge has no server-side id, so the plugin mints
     * one and the Dart side echoes it back on `checkOAuthEmailOTP`; a
     * new attempt supersedes any earlier one and the verification token
     * never crosses the channel.
     */
    private val oauthEmailChallenges: MutableMap<String, CachedOAuthEmailChallenge> =
        mutableMapOf()
    private val lock = Any()

    /**
     * Lookup-or-create runs inside the same lock on purpose: a split
     * read-then-write would let two callers for the same handle both
     * miss the cache, both run the `PreludeAuthClient` constructor
     * (which provisions DPoP key state via Keystore), and the second
     * writer would win — leaving the loser's keystore footprint with
     * no Dart-side reference to dispose it.
     */
    fun resolveClient(
        context: Context,
        handle: String,
        configRaw: Map<*, *>,
    ): PreludeAuthClient =
        synchronized(lock) {
            clients[handle]?.let { return@synchronized it }
            val config = ClientConfig.decode(configRaw)
            val signalsKey = resolveSignalsSDKKey(context, config.signalsKeyOverride)
            // Adapter no-ops when `sdkKey` is null, so we always
            // pass it in. Hides the manifest / override decision
            // from the auth client.
            val dispatcher = PreludeSignalsAdapter(context, signalsKey)
            val client = PreludeAuthClient(
                context = context,
                baseUrl = config.baseUrl,
                hostOverride = config.hostOverride,
                timeout = config.timeout,
                signalsDispatcher = dispatcher,
            )
            clients[handle] = client
            client
        }

    /** Drop the client and any cached state for [handle]. */
    fun dispose(handle: String) {
        synchronized(lock) {
            clients.remove(handle)
            challenges.remove(handle)
            oauthContexts.remove(handle)
            oauthEmailChallenges.remove(handle)
        }
    }

    /** Drop everything; called on engine detach. */
    fun clear() {
        synchronized(lock) {
            clients.clear()
            challenges.clear()
            oauthContexts.clear()
            oauthEmailChallenges.clear()
        }
    }

    /**
     * Insert or replace a challenge under (handle, challengeID).
     * Blocked challenges and the empty challengeID sentinel are
     * skipped: neither is submittable, so caching them would only
     * grow the map.
     */
    fun cacheChallenge(handle: String, challenge: PreludeStepUpChallenge) {
        if (challenge.status == PreludeStepUpStatus.BLOCKED) return
        if (challenge.challengeId.isEmpty()) return
        synchronized(lock) {
            // Don't resurrect entries for a handle that's already
            // been disposed; the writer raced the dispose call.
            if (clients[handle] == null) return
            val slot = challenges.getOrPut(handle) { mutableMapOf() }
            slot[challenge.challengeId] = challenge
        }
    }

    fun evictChallenge(handle: String, challengeId: String) {
        synchronized(lock) {
            val slot = challenges[handle] ?: return
            slot.remove(challengeId)
            if (slot.isEmpty()) challenges.remove(handle)
        }
    }

    /**
     * Resolve a Dart-side challengeID back to the cached challenge.
     * Throws `InvalidChallengeToken` when the challenge is unknown
     * or has expired locally — both recover via
     * `requestStepUp(scope:)` so the consumer handles a single error
     * path.
     */
    fun lookupChallenge(handle: String, challengeId: String): PreludeStepUpChallenge {
        val found = synchronized(lock) { challenges[handle]?.get(challengeId) }
        return found ?: throw PreludeAuthError.InvalidChallengeToken(
            "Step-up challenge `$challengeId` not found. " +
                "Pass the value returned by requestStepUp / submitStepUpOTP " +
                "unchanged, or call requestStepUp(scope:) again.",
        )
    }

    /**
     * Store the latest in-flight OAuth context for [handle], replacing
     * any unredeemed earlier attempt.
     */
    fun cacheOAuthContext(handle: String, context: OAuthLoginContext) {
        synchronized(lock) {
            // Don't resurrect entries for a handle that's already been
            // disposed; the writer raced the dispose call.
            if (clients[handle] == null) return
            oauthContexts[handle] = context
        }
    }

    /**
     * Resolve [handle]'s in-flight OAuth context for finalize. Throws
     * when no initiate is pending — the caller recovers by starting
     * the flow again.
     */
    fun lookupOAuthContext(handle: String): OAuthLoginContext {
        val found = synchronized(lock) { oauthContexts[handle] }
        return found ?: throw PreludeAuthError.InvalidChallengeToken(
            "No in-flight OAuth login for this client. " +
                "Call initiateOAuthLogin before finalizeOAuthLogin.",
        )
    }

    fun evictOAuthContext(handle: String) {
        synchronized(lock) { oauthContexts.remove(handle) }
    }

    /**
     * Cache [challenge] under a freshly minted id and return it. The
     * Dart side echoes the id back on `checkOAuthEmailOTP`. A new
     * attempt supersedes any unredeemed earlier one — only one
     * challenge is ever in flight per handle.
     *
     * Throws `InvalidChallengeToken` when [handle] was disposed mid-flow:
     * the entry can't be cached, so returning its id would hand back a
     * value that `lookupOAuthEmailChallenge` could never resolve.
     */
    fun cacheOAuthEmailChallenge(handle: String, challenge: OAuthEmailChallenge): String {
        val challengeId = UUID.randomUUID().toString()
        synchronized(lock) {
            if (clients[handle] == null) {
                throw PreludeAuthError.InvalidChallengeToken(
                    "Client handle has been disposed. Restart the OAuth login.",
                )
            }
            oauthEmailChallenges[handle] = CachedOAuthEmailChallenge(challengeId, challenge)
        }
        return challengeId
    }

    /**
     * Resolve a Dart-side challengeID back to the cached challenge.
     * Throws `InvalidChallengeToken` when it's unknown or has been
     * superseded — the caller recovers by restarting the OAuth login.
     */
    fun lookupOAuthEmailChallenge(handle: String, challengeId: String): OAuthEmailChallenge {
        val found = synchronized(lock) {
            oauthEmailChallenges[handle]?.takeIf { it.id == challengeId }
        }
        return found?.challenge ?: throw PreludeAuthError.InvalidChallengeToken(
            "OAuth email challenge `$challengeId` not found. " +
                "Pass the value returned by loginWithOAuth / finalizeOAuthLogin " +
                "unchanged, or restart the OAuth login.",
        )
    }

    /**
     * Evict only when [challengeId] still owns the slot, so a late
     * check on a superseded id can't drop a newer attempt's challenge.
     */
    fun evictOAuthEmailChallenge(handle: String, challengeId: String) {
        synchronized(lock) {
            if (oauthEmailChallenges[handle]?.id == challengeId) {
                oauthEmailChallenges.remove(handle)
            }
        }
    }
}
