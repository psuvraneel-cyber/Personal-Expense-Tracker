package com.pet.tracker.pet

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // SmsReaderPlugin is attached to every engine (this one included) by
        // EngineHooksPlugin; see PetApplication.

        // FLAG_SECURE toggle: hides content in Recents and blocks screenshots
        // while the user has App Lock enabled.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pet.tracker/window")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val secure = call.argument<Boolean>("secure") ?: false
                    runOnUiThread {
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }
}
