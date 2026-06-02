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
import android.content.res.AssetManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import java.io.InputStream

/**
 * 弗糯糯电子宠物浮窗 Service v2。
 * 用 PetView (Custom View + 硬件层) 替代旧 ImageView 方案。
 */
class PetForegroundService : Service() {

    private var windowManager: WindowManager? = null
    private var rootView: FrameLayout? = null
    private var petView: PetView? = null
    private var screenReceiver: BroadcastReceiver? = null
    private var density: Float = 1f

    // 点击穿透
    private var isPassthrough = false

    companion object {
        const val CHANNEL_ID = "pet_foreground"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "START_PET"
        const val ACTION_STOP = "STOP_PET"

        @JvmStatic var touchConsumer: ((String, Float, Float) -> Unit)? = null
        @JvmStatic var arriveConsumer: ((Float, Float) -> Unit)? = null
        @JvmStatic var pokeCountConsumer: ((Int) -> Unit)? = null
        @JvmStatic var instance: PetForegroundService? = null
    }

    override fun onCreate() {
        super.onCreate()
        Log.d("PetSvc", "===== Service onCreate v2 =====")
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        density = resources.displayMetrics.density
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

    // ═══════════════════════════════════════════
    // 通知
    // ═══════════════════════════════════════════

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "弗糯糯电子宠物", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "弗糯糯正在陪伴你"
                    setShowBadge(false)
                }
            )
        }
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = Intent(this, PetForegroundService::class.java).apply { action = ACTION_STOP }
        val spi = PendingIntent.getService(this, 0, stop, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("弗糯糯").setContentText("糯糯正在陪你...")
                .setSmallIcon(android.R.drawable.ic_dialog_info).setContentIntent(pi)
                .addAction(android.R.drawable.ic_media_pause, "关闭宠物", spi).setOngoing(true).build()
        else @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("弗糯糯").setContentText("糯糯正在陪你...")
                .setSmallIcon(android.R.drawable.ic_dialog_info).setContentIntent(pi).setOngoing(true).build()
    }

    // ═══════════════════════════════════════════
    // 浮窗显示
    // ═══════════════════════════════════════════

    private fun showPetWindow() {
        Log.d("PetSvc", "=== showPetWindow v2 ===")
        startForeground(NOTIFICATION_ID, buildNotification())

        if (rootView?.parent != null) return

        val sizePx = (120 * density).toInt()

        // 创建 PetView
        petView = PetView(this).apply {
            layoutParams = FrameLayout.LayoutParams(sizePx, sizePx)
            petWidth = sizePx.toFloat()
            petHeight = sizePx.toFloat()

            // 触控回调
            onTouchEvent = { type, x, y ->
                Log.d("PetSvc", "touch: $type ($x, $y)")
                touchConsumer?.invoke(type, x, y)
            }
            onPokeCount = { count ->
                pokeCountConsumer?.invoke(count)
            }
            onArrive = { x, y ->
                arriveConsumer?.invoke(x, y)
            }
        }

        // 加载帧动画（在创建 PetView 之后）
        loadAllFrames()
        if (petView?.listAnimNames()?.isNotEmpty() == true) {
            petView?.playAnim("idle")
        }

        rootView = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(sizePx, sizePx)
            addView(petView)
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS

        val params = WindowManager.LayoutParams(sizePx, sizePx, type, flags, PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.START; x = 100; y = 400
        }

        windowManager?.addView(rootView, params)
        startMonitoring()

        // 启动渲染循环
        petView?.startRenderLoop()
        Log.d("PetSvc", "=== showPetWindow v2 COMPLETE ===")
    }

    // ═══════════════════════════════════════════
    // 帧加载（从 assets/pet_frames/）
    // ═══════════════════════════════════════════

    private fun loadAllFrames() {
        try {
            for (state in listOf("idle", "hungry", "sleeping", "talking")) {
                val path = "pet_frames/$state"
                val files = assets.list(path) ?: continue
                files.sort()
                val frames = mutableListOf<Bitmap>()
                for (name in files) {
                    if (!name.endsWith(".png")) continue
                    var stream: InputStream? = null
                    try {
                        stream = assets.open("$path/$name")
                        val bmp = BitmapFactory.decodeStream(stream)
                        if (bmp != null) frames.add(bmp)
                    } finally { stream?.close() }
                }
                if (frames.isNotEmpty()) {
                    val interval = when (state) {
                        "sleeping" -> 500L
                        "idle", "talking" -> 67L
                        "hungry" -> 100L
                        else -> 80L
                    }
                    petView?.registerAnim(state, frames, interval, loop = true)
                    Log.d("PetSvc", "loaded $state: ${frames.size} frames @${interval}ms")
                }
            }
        } catch (e: Exception) {
            Log.e("PetSvc", "loadFrames failed: ${e.message}")
        }
    }

    // ═══════════════════════════════════════════
    // 命令接口（由 MainActivity 调用）
    // ═══════════════════════════════════════════

    fun handleCommand(cmd: String, args: Map<String, Any>?) {
        Log.d("PetSvc", ">>> cmd IN: $cmd ${args?.toString() ?: "{}"}")
        val pv = petView
        when (cmd) {
            "playAnim" -> {
                val animName = (args?.get("anim") as? String) ?: "idle"
                // 情绪变体
                val emotionSpeed = (args?.get("emotionSpeed") as? Number)?.toFloat() ?: 1f
                val emotionSat = (args?.get("emotionSaturation") as? Number)?.toFloat() ?: 1f
                val emotionGray = (args?.get("emotionGrayscale") as? Number)?.toFloat() ?: 0f
                pv?.setEmotion(emotionSpeed, emotionSat, emotionGray)
                pv?.playAnim(animName)
                Log.d("PetSvc", "<<< cmd DONE playAnim: $animName")
            }
            "showBubble" -> {
                val text = (args?.get("text") as? String) ?: ""
                val durationMs = (args?.get("durationMs") as? Number)?.toLong() ?: 3000L
                pv?.showBubble(text, durationMs)
                Log.d("PetSvc", "<<< cmd DONE showBubble: '$text'")
            }
            "hideBubble" -> {
                pv?.bubble?.hide()
                Log.d("PetSvc", "<<< cmd DONE hideBubble")
            }
            "showEmoji" -> {
                // Emoji 已通过 PetView 的 BubbleAnimator 处理
                val emoji = (args?.get("emoji") as? String) ?: ""
                pv?.showBubble(emoji, 2000)
                Log.d("PetSvc", "<<< cmd DONE showEmoji: '$emoji'")
            }
            "hideEmoji" -> {
                pv?.bubble?.hide()
                Log.d("PetSvc", "<<< cmd DONE hideEmoji")
            }
            "setPos" -> {
                val x = (args?.get("x") as? Int) ?: 100
                val y = (args?.get("y") as? Int) ?: 400
                val lp = rootView?.layoutParams as? WindowManager.LayoutParams
                if (lp != null) {
                    lp.x = x; lp.y = y
                    windowManager?.updateViewLayout(rootView, lp)
                }
                pv?.physics?.x = x.toFloat()
                pv?.physics?.y = y.toFloat()
                Log.d("PetSvc", "<<< cmd DONE setPos: ($x, $y)")
            }
            "setSize" -> {
                val w = ((args?.get("width") as? Number)?.toInt() ?: 120) * density
                val h = ((args?.get("height") as? Number)?.toInt() ?: 120) * density
                val lp = rootView?.layoutParams as? WindowManager.LayoutParams
                if (lp != null) {
                    lp.width = w.toInt(); lp.height = h.toInt()
                    windowManager?.updateViewLayout(rootView, lp)
                }
                pv?.petWidth = w; pv?.petHeight = h
                Log.d("PetSvc", "<<< cmd DONE setSize: ${w.toInt()}x${h.toInt()}")
            }
            "moveTo" -> {
                val x = (args?.get("x") as? Number)?.toFloat() ?: pv?.physics?.x ?: 100f
                val y = (args?.get("y") as? Number)?.toFloat() ?: pv?.physics?.y ?: 400f
                val speed = (args?.get("speed") as? Number)?.toFloat() ?: 200f
                pv?.moveTo(x, y, speed)
                Log.d("PetSvc", "<<< cmd DONE moveTo: ($x, $y) speed=$speed")
            }
            "setPassthrough" -> {
                val enabled = args?.get("enabled") as? Boolean ?: false
                setPassthrough(enabled)
                Log.d("PetSvc", "<<< cmd DONE setPassthrough: $enabled")
            }
            "setFacing" -> {
                val left = args?.get("left") as? Boolean ?: false
                pv?.setFacing(left)
                Log.d("PetSvc", "<<< cmd DONE setFacing: left=$left")
            }
            "setFps" -> {
                val fps = (args?.get("fps") as? Number)?.toInt() ?: 60
                pv?.setFps(fps)
                Log.d("PetSvc", "<<< cmd DONE setFps: $fps")
            }
            "close" -> {
                Log.d("PetSvc", "<<< cmd DONE close -> hidePetWindow")
                hidePetWindow()
            }
        }
    }

    // ═══════════════════════════════════════════
    // 点击穿透
    // ═══════════════════════════════════════════

    private fun setPassthrough(enabled: Boolean) {
        if (isPassthrough == enabled) return
        isPassthrough = enabled
        val lp = rootView?.layoutParams as? WindowManager.LayoutParams ?: return
        if (enabled) {
            lp.flags = lp.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        } else {
            lp.flags = lp.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        }
        windowManager?.updateViewLayout(rootView, lp)
        petView?.setPassthrough(enabled)
    }

    // ═══════════════════════════════════════════
    // 屏幕/电量监控
    // ═══════════════════════════════════════════

    private fun startMonitoring() {
        stopMonitoring()
        sendBatteryStatus()
        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> {
                        Log.d("PetSvc", "screen OFF")
                        petView?.stopRenderLoop()
                        touchConsumer?.invoke("screen", -1f, -1f)
                    }
                    Intent.ACTION_SCREEN_ON -> {
                        Log.d("PetSvc", "screen ON")
                        petView?.startRenderLoop()
                        touchConsumer?.invoke("screen", -2f, -2f)
                    }
                }
            }
        }
        registerReceiver(screenReceiver, IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF); addAction(Intent.ACTION_SCREEN_ON)
        })
    }

    private fun sendBatteryStatus() {
        val bi = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = bi?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = bi?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val pct = if (scale > 0) (level * 100 / scale) else -1
        val chg = bi?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) == BatteryManager.BATTERY_STATUS_CHARGING
        Log.d("PetSvc", "battery: $pct% charging=$chg")

        // 电量<15% → 降帧
        if (pct in 1..14) petView?.setFps(15)
        else petView?.setFps(60)

        touchConsumer?.invoke("battery", pct.toFloat(), if (chg) 1f else 0f)
    }

    private fun stopMonitoring() {
        screenReceiver?.let { try { unregisterReceiver(it) } catch (_: Exception) {} }; screenReceiver = null
    }

    private fun hidePetWindow() {
        stopMonitoring()
        petView?.stopRenderLoop()
        rootView?.let { try { windowManager?.removeView(it) } catch (_: IllegalArgumentException) {} }
        rootView = null; petView = null
        stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
    }

    override fun onDestroy() {
        Log.d("PetSvc", "===== Service onDestroy v2 =====")
        instance = null
        hidePetWindow()
        super.onDestroy()
    }
}
