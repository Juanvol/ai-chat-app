package com.example.deepseek_chat

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // pet_service channel: 启动/停止/权限
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.deepseek_chat/pet_service").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startPet" -> { startPetService(); result.success(true) }
                    "stopPet" -> { stopPetService(); result.success(true) }
                    "isOverlayPermissionGranted" -> result.success(Settings.canDrawOverlays(this@MainActivity))
                    "requestOverlayPermission" -> {
                        startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // pet_overlay channel: 命令转发 + 触控回传
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.deepseek_chat/pet_overlay").apply {
            // Service → Dart 触控回调
            PetForegroundService.touchConsumer = { type, x, y ->
                invokeMethod("onTouch", mapOf("type" to type, "x" to x, "y" to y))
            }
            PetForegroundService.arriveConsumer = { x, y ->
                invokeMethod("onTouch", mapOf("type" to "arrive", "x" to x, "y" to y))
            }
            PetForegroundService.pokeCountConsumer = { count ->
                invokeMethod("onTouch", mapOf("type" to "pokeCount", "count" to count))
            }

            setMethodCallHandler { call, result ->
                val svc = PetForegroundService.instance
                when (call.method) {
                    "cmd" -> {
                        val cmd = call.argument<String>("cmd") ?: ""
                        @Suppress("UNCHECKED_CAST")
                        val args = call.argument<Map<String, Any>>("args")
                        svc?.handleCommand(cmd, args)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // pet_agent_bridge: 内部通信桥
        // MiniChat → chatReq → Android → EngineBridge.invokeMain() → main.dart → PetAgentCore
        // PetAgentCore → chatChunk/Done/Error → Android → EngineBridge.invokePetWindow() → MiniChat
        val agentChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.deepseek_chat/pet_agent_bridge")
        EngineBridge.registerMain(flutterEngine.dartExecutor.binaryMessenger)
        // 单引擎架构：PetForegroundService 使用原生 Overlay（无 Flutter Engine），
        // MiniChat 在同一引擎内，因此 invokePetWindow 与 invokeMain 共用同一个 messenger
        EngineBridge.registerPetWindow(flutterEngine.dartExecutor.binaryMessenger)

        agentChannel.setMethodCallHandler { call, result ->
            Log.d("MainActivity", "pet_agent_bridge: ${call.method}")
            when (call.method) {
                "chatReq" -> {
                    @Suppress("UNCHECKED_CAST")
                    EngineBridge.invokeMain(call.method, call.arguments as Map<String, Any?>)
                    result.success(null)
                }
                "chatChunk", "chatDone", "chatError" -> {
                    @Suppress("UNCHECKED_CAST")
                    EngineBridge.invokePetWindow(call.method, call.arguments as Map<String, Any?>)
                    result.success(null)
                }
                "getPopupHistory" -> {
                    val history = PetForegroundService.instance?.getPopupHistory()
                        ?: emptyList<Map<String, Any>>()
                    result.success(history)
                }
                "clearPopupHistory" -> {
                    PetForegroundService.instance?.clearPopupHistory()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun startPetService() {
        val intent = Intent(this, PetForegroundService::class.java).apply { action = PetForegroundService.ACTION_START }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
    }

    fun stopPetService() {
        // stopService() 直接触发 onDestroy()，不经过 onStartCommand
        // 避免 startService(ACTION_STOP) 导致的 创建→销毁 循环
        stopService(Intent(this, PetForegroundService::class.java))
    }
}
