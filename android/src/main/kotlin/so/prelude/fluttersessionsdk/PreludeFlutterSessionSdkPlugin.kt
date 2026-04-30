package so.prelude.fluttersessionsdk

import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * Android plugin for the Flutter Session SDK.
 *
 * Registers a method channel and answers `getPlatformVersion` so
 * the channel can be exercised end to end. Every other call is
 * reported back to Dart as `notImplemented` — 0.1.0 ships
 * iOS-only feature coverage on purpose, so Dart surfaces
 * `MissingPluginException` on Android. Per-method bridges to
 * `so.prelude.android:sessions` (`PreludeSessionClient`) land
 * together with the native dependency in a future release.
 */
class PreludeFlutterSessionSdkPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    @Volatile
    private var androidContext: Context? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "prelude_so_flutter_session_sdk")
        channel.setMethodCallHandler(this)
        androidContext = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
        androidContext = null
    }
}
