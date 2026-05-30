package com.example.deepseek_chat

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.deepseek_chat/pet_service").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startPet" -> {
                        startPetService()
                        result.success(true)
                    }
                    "stopPet" -> {
                        stopPetService()
                        result.success(true)
                    }
                    "isOverlayPermissionGranted" -> {
                        result.success(Settings.canDrawOverlays(this@MainActivity))
                    }
                    "requestOverlayPermission" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // pet_agent_bridge channel: 接收引擎 #1 Dart 端（PetAgentCore）的 invokeMethod，转发到引擎 #2
        EngineBridge.registerMain(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.deepseek_chat/pet_agent_bridge").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "chatChunk" -> {
                        val fullText = call.argument<String>("fullText") ?: ""
                        val requestId = call.argument<Int>("requestId") ?: 0
                        EngineBridge.invokePetWindow("chatChunk", mapOf(
                            "fullText" to fullText,
                            "requestId" to requestId
                        ))
                        result.success(null)
                    }
                    "chatDone" -> {
                        val requestId = call.argument<Int>("requestId") ?: 0
                        EngineBridge.invokePetWindow("chatDone", mapOf("requestId" to requestId))
                        result.success(null)
                    }
                    "chatError" -> {
                        val message = call.argument<String>("message") ?: "未知错误"
                        val requestId = call.argument<Int>("requestId") ?: 0
                        EngineBridge.invokePetWindow("chatError", mapOf(
                            "message" to message,
                            "requestId" to requestId
                        ))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun startPetService() {
        val intent = Intent(this, PetForegroundService::class.java).apply {
            action = PetForegroundService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    fun stopPetService() {
        val intent = Intent(this, PetForegroundService::class.java).apply {
            action = PetForegroundService.ACTION_STOP
        }
        startService(intent)
    }
}
