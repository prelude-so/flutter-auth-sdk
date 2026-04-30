package so.prelude.fluttersessionsdk

import so.prelude.android.session.PreludeJSONValue
import so.prelude.android.session.PreludePasswordCompliancy
import so.prelude.android.session.PreludeProfile
import so.prelude.android.session.PreludeStepUpChallenge
import so.prelude.android.session.PreludeUser

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
