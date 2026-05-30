package com.example.deepseek_chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.PixelFormat
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.WindowManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class PetForegroundService : Service() {

    private var flutterEngine: FlutterEngine? = null
    private var windowManager: WindowManager? = null
    private var petView: android.view.View? = null
    private var petChannel: MethodChannel? = null
    private var screenReceiver: BroadcastReceiver? = null

    companion object {
        const val CHANNEL_ID = "pet_foreground"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "START_PET"
        const val ACTION_STOP = "STOP_PET"
        const val METHOD_CHANNEL = "com.example.deepseek_chat/pet_window"
    }

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> showPetWindow()
            ACTION_STOP -> hidePetWindow()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "弗糯糯电子宠物",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "弗糯糯正在陪伴你"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, PetForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("弗糯糯")
                .setContentText("糯糯正在陪你...")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(pendingIntent)
                .addAction(android.R.drawable.ic_media_pause, "关闭宠物", stopPendingIntent)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("弗糯糯")
                .setContentText("糯糯正在陪你...")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        }
    }

    private fun showPetWindow() {
        startForeground(NOTIFICATION_ID, buildNotification())

        // 防止重复 addView 崩溃
        if (petView != null && petView?.parent != null) return

        if (flutterEngine == null) {
            val bundlePath = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            if (bundlePath == null) return
            flutterEngine = FlutterEngine(this).apply {
                dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(bundlePath, "petMain")
                )
            }
        }

        val surfaceView = FlutterSurfaceView(this)
        surfaceView.attachToRenderer(flutterEngine!!.getRenderer())
        petView = surfaceView

        setupMethodChannel()
        startMonitoring()

        val density = resources.displayMetrics.density
        val sizePx = (120 * density).toInt()

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS

        val params = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            type,
            flags,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 100
            y = 400
        }

        windowManager?.addView(petView, params)
    }

    private fun setupMethodChannel() {
        val engine = flutterEngine ?: return
        petChannel = MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        petChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "moveWindow" -> {
                    val dx = call.argument<Int>("dx") ?: 0
                    val dy = call.argument<Int>("dy") ?: 0
                    val params = petView?.layoutParams as? WindowManager.LayoutParams
                    params?.let {
                        it.x += dx
                        it.y += dy
                        windowManager?.updateViewLayout(petView, it)
                    }
                    result.success(null)
                }
                "setWindowSize" -> {
                    val width = call.argument<Int>("width") ?: 120
                    val height = call.argument<Int>("height") ?: 120
                    val density = resources.displayMetrics.density
                    val params = petView?.layoutParams as? WindowManager.LayoutParams
                    params?.let {
                        it.width = (width * density).toInt()
                        it.height = (height * density).toInt()
                        windowManager?.updateViewLayout(petView, it)
                    }
                    result.success(null)
                }
                "getWindowSize" -> {
                    val params = petView?.layoutParams as? WindowManager.LayoutParams
                    val density = resources.displayMetrics.density
                    val w = ((params?.width ?: 0) / density).toInt()
                    val h = ((params?.height ?: 0) / density).toInt()
                    result.success(mapOf("width" to w, "height" to h))
                }
                "getWindowPos" -> {
                    val params = petView?.layoutParams as? WindowManager.LayoutParams
                    result.success(mapOf("x" to (params?.x ?: 0), "y" to (params?.y ?: 0)))
                }
                "setFocusable" -> {
                    val focusable = call.argument<Boolean>("focusable") ?: false
                    val params = petView?.layoutParams as? WindowManager.LayoutParams
                    params?.let {
                        if (focusable) {
                            it.flags = it.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
                        } else {
                            it.flags = it.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        }
                        windowManager?.updateViewLayout(petView, it)
                    }
                    result.success(null)
                }
                "openMainApp" -> {
                    val intent = packageManager.getLaunchIntentForPackage(packageName)
                    intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    startActivity(intent)
                    result.success(null)
                }
                "closePet" -> {
                    hidePetWindow()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // pet_agent_bridge channel: 接收 MiniChat 的 chatReq，转发到引擎 #1
        val agentChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.example.deepseek_chat/pet_agent_bridge")
        agentChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "chatReq" -> {
                    val text = call.argument<String>("text") ?: ""
                    val history = call.argument<List<Map<String, String>>>("history") ?: emptyList()
                    val requestId = call.argument<Int>("requestId") ?: 0
                    EngineBridge.invokeMain("chatReq", mapOf(
                        "text" to text,
                        "history" to history,
                        "requestId" to requestId
                    ))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EngineBridge.registerPetWindow(engine.dartExecutor.binaryMessenger)
    }

    private fun startMonitoring() {
        // 防止重复注册
        stopMonitoring()
        sendBatteryStatus()
        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> petChannel?.invokeMethod("onScreenOff", null)
                    Intent.ACTION_SCREEN_ON -> petChannel?.invokeMethod("onScreenOn", null)
                }
            }
        }
        val screenFilter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        registerReceiver(screenReceiver, screenFilter)
    }

    private fun sendBatteryStatus() {
        val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val percent = if (scale > 0) (level * 100 / scale) else -1
        val charging = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ==
                BatteryManager.BATTERY_STATUS_CHARGING
        petChannel?.invokeMethod("onBatteryChanged", mapOf("level" to percent, "charging" to charging))
    }

    private fun stopMonitoring() {
        screenReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
            screenReceiver = null
        }
    }

    private fun hidePetWindow() {
        stopMonitoring()
        EngineBridge.clearPetWindow()
        petChannel = null
        petView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (_: IllegalArgumentException) { }
        }
        petView = null
        flutterEngine?.destroy()
        flutterEngine = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        hidePetWindow()
        super.onDestroy()
    }

    override fun onLowMemory() {
        stopMonitoring()
        flutterEngine?.destroy()
        flutterEngine = null
        petView = null
        petChannel = null
        super.onLowMemory()
    }
}
