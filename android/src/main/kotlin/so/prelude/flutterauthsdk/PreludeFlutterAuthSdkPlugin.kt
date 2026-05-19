// PreludeFlutterAuthSdkPlugin
//
// Android plugin for the Flutter Auth SDK. Bridges the Dart
// `PreludeAuthClient` API onto the native auth client.
//
// One Dart instance maps to one native client, looked up by the
// per-instance handle string the Dart side stamps at construction.
// Native clients are created lazily on first use and reused for
// the lifetime of the handle so DPoP keys, refresh tokens, and
// the access-token cache stay stable across calls.
//
// In-flight step-up challenges are cached on the native side
// (see [ClientRegistry]), so the wire form sent across the channel
// can omit the bearer challenge token.

package so.prelude.flutterauthsdk

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class PreludeFlutterAuthSdkPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel

    /**
     * Long-lived scope for async method dispatch. `SupervisorJob`
     * so a failure in one call doesn't cascade across siblings;
     * `Dispatchers.IO` because the SDK does blocking SharedPreferences
     * + Keystore work on first use and the cooperative network round-
     * trips downstream.
     */
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * `FlutterResult` callbacks must fire on the binary messenger's
     * thread (main). Hopping back via a [Handler] avoids pulling in
     * the `Dispatchers.Main` artifact for what is one trampoline per
     * call.
     */
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Application context captured at engine attach. `@Volatile` so
     * the detach write publishes immediately to in-flight method
     * calls reading on the IO dispatcher.
     */
    @Volatile
    private var androidContext: Context? = null

    private val registry = ClientRegistry()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "prelude_so_flutter_auth_sdk")
        channel.setMethodCallHandler(this)
        androidContext = binding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        // Methods that don't need a native client live on the
        // synchronous side so we don't pay for a coroutine hop.
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${Build.VERSION.RELEASE}")
                return
            }
            "dispose" -> {
                handleDispose(call, result)
                return
            }
        }

        // Reject unknown methods before resolving the client.
        // Otherwise a typo'd method name would still mint DPoP keys
        // and read SharedPreferences just to answer "not implemented".
        if (call.method !in ASYNC_METHODS) {
            result.notImplemented()
            return
        }

        val args = call.arguments as? Map<*, *>
        val handle = args?.get("handle") as? String
        val configRaw = args?.get("config") as? Map<*, *>
        if (args == null || handle == null || configRaw == null) {
            result.error("bad_request", "${call.method}: malformed arguments", null)
            return
        }

        val context = androidContext
        if (context == null) {
            result.error("bad_request", "${call.method}: plugin detached", null)
            return
        }

        // Resolve + dispatch run on `Dispatchers.IO`, not the main
        // thread. `resolveClient` lazily provisions the native client
        // on first use, which hits SharedPreferences (access-token
        // cache hydration) and, on the very first call per process,
        // the AndroidKeystore probe. Doing that work here would
        // block the Flutter messenger thread.
        scope.launch {
            try {
                val client = registry.resolveClient(context, handle, configRaw)
                deliverSuccess(dispatch(call, args, handle, client, registry), result)
            } catch (e: CancellationException) {
                // Structured-concurrency cancellation must propagate
                // as-is. The Result is left without a reply only when
                // the engine is being torn down (scope cancel on
                // detach), at which point the channel is gone too.
                throw e
            } catch (e: Throwable) {
                deliverError(e, result)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
        registry.clear()
        androidContext = null
    }

    private fun handleDispose(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val handle = args?.get("handle") as? String
        if (handle == null) {
            result.error("bad_request", "dispose: malformed arguments", null)
            return
        }
        registry.dispose(handle)
        result.success(null)
    }

    /**
     * Forward `value` to `result` on the platform (main) thread.
     * Synchronous call sites already run on main; only async
     * dispatch needs the Handler hop.
     */
    private fun deliverSuccess(value: Any?, result: Result) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            result.success(value)
        } else {
            mainHandler.post { result.success(value) }
        }
    }

    private fun deliverError(error: Throwable, result: Result) {
        val mapped = mapError(error)
        if (Looper.myLooper() == Looper.getMainLooper()) {
            result.error(mapped.code, mapped.message, null)
        } else {
            mainHandler.post { result.error(mapped.code, mapped.message, null) }
        }
    }
}
