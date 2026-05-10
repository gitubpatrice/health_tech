package com.filestech.health_tech

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// FlutterFragmentActivity (rather than FlutterActivity) is required by
/// androidx.biometric.BiometricPrompt, which expects a FragmentActivity to
/// host its prompt fragment.
class MainActivity : FlutterFragmentActivity() {

    private val secureChannel = "com.filestech.health_tech/secure_window"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        runOnUiThread {
                            window.setFlags(
                                WindowManager.LayoutParams.FLAG_SECURE,
                                WindowManager.LayoutParams.FLAG_SECURE,
                            )
                        }
                        result.success(true)
                    }
                    "disable" -> {
                        // FLAG_SECURE is non-negotiable for medical / wellness data.
                        result.error("forbidden", "FLAG_SECURE cannot be cleared", null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Wire the biometric bridge. It lives only as long as the activity,
        // so re-installing it on every engine attach is safe.
        BiometricBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
