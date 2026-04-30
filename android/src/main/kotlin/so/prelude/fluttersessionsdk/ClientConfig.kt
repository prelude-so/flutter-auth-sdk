package so.prelude.fluttersessionsdk

import so.prelude.android.session.LoginWithPasswordOptions
import so.prelude.android.session.PreludeIdentifier
import so.prelude.android.session.PreludeIdentifierType
import so.prelude.android.session.PreludeSessionError
import so.prelude.android.session.RedactedString
import so.prelude.android.session.StartOTPLoginOptions
import java.net.MalformedURLException
import java.net.URL
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Snapshot of the Dart-side `ClientConfig` decoded for the native
 * constructor. Held only for the lifetime of one client construction.
 */
internal data class ClientConfig(
    val baseUrl: URL,
    val hostOverride: String?,
    val timeout: Duration,
) {
    companion object {
        /** Canonical Prelude API address; matches the iOS default. */
        private const val DEFAULT_BASE_URL = "https://api.prelude.dev"

        fun decode(raw: Map<*, *>): ClientConfig {
            val endpointRaw = raw["endpoint"] as? Map<*, *>
                ?: throw decodeError("config.endpoint missing or wrong shape")
            val address = when (endpointRaw["kind"] as? String) {
                "default" -> DEFAULT_BASE_URL
                "custom" -> endpointRaw["address"] as? String
                    ?: throw decodeError("Endpoint.custom missing address")
                else -> throw decodeError("Unknown Endpoint kind")
            }
            val baseUrl = try {
                URL(address)
            } catch (_: MalformedURLException) {
                throw PreludeSessionError.InvalidConfiguration(
                    "Endpoint address `$address` is not a valid URL",
                )
            }
            // `timeoutSeconds` arrives as either Double or Int.
            val timeoutSecs = (raw["timeoutSeconds"] as? Number)?.toDouble() ?: 10.0
            // `allowInsecureTLS` is intentionally not threaded
            // through: the native Android client doesn't expose a
            // hook for it. Local-development trust overrides belong
            // in the consuming app's `network_security_config.xml`.
            return ClientConfig(
                baseUrl = baseUrl,
                hostOverride = raw["hostOverride"] as? String,
                timeout = timeoutSecs.seconds,
            )
        }
    }
}

internal fun decodeStartOTPLoginOptions(raw: Any?): StartOTPLoginOptions {
    val json = raw as? Map<*, *>
        ?: throw decodeError("StartOTPLoginOptions: malformed payload")
    val identifierRaw = json["identifier"] as? Map<*, *>
        ?: throw decodeError("StartOTPLoginOptions: malformed payload")
    val typeWire = identifierRaw["type"] as? String
        ?: throw decodeError("StartOTPLoginOptions: malformed payload")
    val value = identifierRaw["value"] as? String
        ?: throw decodeError("StartOTPLoginOptions: malformed payload")
    val type = PreludeIdentifierType.entries.firstOrNull { it.wireValue == typeWire }
        ?: throw decodeError("Unknown PreludeIdentifierType: $typeWire")
    return StartOTPLoginOptions(
        identifier = PreludeIdentifier(type = type, value = value),
        loginConfigId = json["loginConfigID"] as? String,
    )
}

internal fun decodeLoginWithPasswordOptions(raw: Any?): LoginWithPasswordOptions {
    val json = raw as? Map<*, *>
        ?: throw decodeError("LoginWithPasswordOptions: malformed payload")
    val email = json["emailAddress"] as? String
        ?: throw decodeError("LoginWithPasswordOptions: malformed payload")
    val password = json["password"] as? String
        ?: throw decodeError("LoginWithPasswordOptions: malformed payload")
    // Wrap in [RedactedString] at the bridge boundary so the only
    // named local holding the plaintext is `password` above.
    return LoginWithPasswordOptions(
        identifier = email,
        password = RedactedString(password),
    )
}
