package com.badeel.servepos.waiter

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is required by local_auth (BiometricPrompt).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "servepos/window")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.argument<Boolean>("secure") ?: false
                        runOnUiThread {
                            if (secure) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Short confirmation tones after Send (sent / saved for later / refused).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "servepos/feedback")
            .setMethodCallHandler { call, result ->
                if (call.method != "tone") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val tone = when (call.argument<String>("kind")) {
                    "ok" -> ToneGenerator.TONE_PROP_ACK
                    "error" -> ToneGenerator.TONE_PROP_NACK
                    else -> ToneGenerator.TONE_PROP_PROMPT
                }
                try {
                    val gen = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 90)
                    gen.startTone(tone, 300)
                    Handler(Looper.getMainLooper()).postDelayed({ gen.release() }, 600)
                } catch (e: RuntimeException) {
                    // No audio resources: haptics still fire on the Dart side.
                }
                result.success(null)
            }
    }
}
