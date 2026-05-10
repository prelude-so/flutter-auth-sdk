package so.prelude.fluttersessionsdk

import android.content.Context
import so.prelude.android.sdk.Configuration
import so.prelude.android.sdk.Prelude
import so.prelude.android.session.signals.PreludeSignalsDispatcher

/**
 * Forwards [PreludeSignalsDispatcher.dispatch] calls into the
 * native `so.prelude.android:sdk` signals subsystem.
 *
 * `null` / blank `sdkKey` is a permissive no-op — the same shape
 * the iOS adapter uses. The session client treats `null` as
 * "skip signals on this call", so the adapter stays in the chain
 * regardless of whether a key was configured.
 */
internal class PreludeSignalsAdapter(
    context: Context,
    sdkKey: String?,
) : PreludeSignalsDispatcher {
    private val prelude: Prelude? =
        sdkKey
            ?.takeIf { it.isNotBlank() }
            ?.let { Prelude(Configuration(context.applicationContext, it)) }

    override suspend fun dispatch(): String? {
        val client = prelude ?: return null
        // The suspend variant returns `Result<String>` — surface
        // failures so the session client's wrapper can decide
        // whether to drop `dispatch_id` or fail the login. The
        // session SDK currently swallows + logs; we leave that
        // policy to it.
        return client.dispatchSignals().getOrThrow()
    }
}
