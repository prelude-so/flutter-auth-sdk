package so.prelude.flutterauthsdk

import so.prelude.android.auth.PreludeJSONValue
import so.prelude.android.auth.PreludeListSessionsResponse
import so.prelude.android.auth.PreludePasskeyCredential
import so.prelude.android.auth.PreludePasskeyRegistration
import so.prelude.android.auth.PreludePasswordCompliancy
import so.prelude.android.auth.PreludeProfile
import so.prelude.android.auth.PreludeSessionView
import so.prelude.android.auth.PreludeStepUpChallenge
import so.prelude.android.auth.PreludeUser
import java.time.format.DateTimeFormatter

/** Encodes native value types into Dart-friendly maps. */
internal object Codec {
    fun encodeUser(user: PreludeUser): Map<String, Any?> =
        mapOf(
            "accessToken" to user.accessToken,
            "profile" to encodeProfile(user.profile),
        )

    fun encodeProfile(profile: PreludeProfile): Map<String, Any?> {
        val extras = mutableMapOf<String, Any?>()
        for ((k, v) in profile.extras) extras[k] = encodeJson(v)
        return mapOf(
            "userID" to profile.userId,
            "sessionID" to profile.sessionId,
            "extras" to extras,
        )
    }

    fun encodeCompliancy(c: PreludePasswordCompliancy): Map<String, Any?> =
        mapOf(
            "minLength" to c.minLength,
            "maxLength" to c.maxLength,
            "uppercase" to c.uppercase,
            "lowercase" to c.lowercase,
            "numbers" to c.numbers,
            "symbols" to c.symbols,
        )

    fun encodeSessionView(v: PreludeSessionView): Map<String, Any?> =
        mapOf(
            "id" to v.id,
            "deviceModel" to v.deviceModel,
            "deviceType" to v.deviceType.wireValue,
            "osVersion" to v.osVersion,
            "countryCode" to v.countryCode,
            // Round-trip as ISO 8601 UTC strings — matches what the
            // iOS bridge ships and what `DateTime.parse` expects on
            // the Dart side.
            "createdAt" to DateTimeFormatter.ISO_INSTANT.format(v.createdAt),
            "lastSeenAt" to DateTimeFormatter.ISO_INSTANT.format(v.lastSeenAt),
            "expiresAt" to DateTimeFormatter.ISO_INSTANT.format(v.expiresAt),
        )

    fun encodeListSessions(r: PreludeListSessionsResponse): Map<String, Any?> =
        mapOf(
            "sessions" to r.sessions.map { encodeSessionView(it) },
            "total" to r.total,
            "limit" to r.limit,
            "offset" to r.offset,
        )

    /**
     * Encode the public-surface fields only. The challenge JWT and
     * expiry stay in the plugin's per-handle cache so the bearer
     * credential never crosses the channel.
     */
    fun encodeChallenge(c: PreludeStepUpChallenge): Map<String, Any?> =
        mapOf(
            "status" to c.status.wireValue,
            "challengeID" to c.challengeId,
            "currentStep" to c.currentStep,
            "requestedScope" to c.requestedScope,
        )

    fun encodeCredential(c: PreludePasskeyCredential): Map<String, Any?> =
        mapOf(
            "credentialID" to c.credentialId,
            "nickname" to c.nickname,
            "transports" to c.transports,
            "backupState" to c.backupState,
            "createdAt" to c.createdAt,
            "lastUsedAt" to c.lastUsedAt,
        )

    fun encodeRegistration(r: PreludePasskeyRegistration): Map<String, Any?> =
        mapOf(
            "credential" to encodeCredential(r.credential),
            "alreadyRegistered" to r.alreadyRegistered,
        )

    /**
     * Tagged JSON encoding so 64-bit-int claims survive the channel
     * without dropping precision through `Double`.
     */
    fun encodeJson(value: PreludeJSONValue): Map<String, Any?> =
        when (value) {
            is PreludeJSONValue.Str -> mapOf("kind" to "string", "value" to value.value)
            is PreludeJSONValue.Int -> mapOf("kind" to "int", "value" to value.value)
            is PreludeJSONValue.Double -> mapOf("kind" to "double", "value" to value.value)
            is PreludeJSONValue.Bool -> mapOf("kind" to "bool", "value" to value.value)
            is PreludeJSONValue.Array -> mapOf(
                "kind" to "array",
                "value" to value.value.map { encodeJson(it) },
            )
            is PreludeJSONValue.Object -> {
                val bridged = mutableMapOf<String, Any?>()
                for ((k, v) in value.value) bridged[k] = encodeJson(v)
                mapOf("kind" to "object", "value" to bridged)
            }
            PreludeJSONValue.Null -> mapOf("kind" to "null")
        }
}
