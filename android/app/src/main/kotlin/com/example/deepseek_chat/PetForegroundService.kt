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
    // 浮窗 LayoutParams（小窗模式重定位用）
    private var windowParams: WindowManager.LayoutParams? = null

    companion object {
        const val CHANNEL_ID = "pet_foreground"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "START_PET"
        const val ACTION_STOP = "STOP_PET"
        const val ACTION_INTERACT = "INTERACT_PET"

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
            ACTION_INTERACT -> enableInteraction()
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
        val interact = Intent(this, PetForegroundService::class.java).apply { action = ACTION_INTERACT }
        val ipi = PendingIntent.getService(this, 1, interact, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("弗糯糯").setContentText("糯糯正在陪你...")
                .setSmallIcon(android.R.drawable.ic_dialog_info).setContentIntent(pi)
                .addAction(android.R.drawable.ic_menu_edit, "交互", ipi)
                .addAction(android.R.drawable.ic_media_pause, "关闭", spi).setOngoing(true).build()
        else @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("弗糯糯").setContentText("糯糯正在陪你...")
                .setSmallIcon(android.R.drawable.ic_dialog_info).setContentIntent(pi).setOngoing(true).build()
    }

    // ═══════════════════════════════════════════
    // 浮窗显示
    // ═══════════════════════════════════════════

    private fun showPetWindow() {
        Log.d("PetSvc", "=== showPetWindow v4 (dynamic window) ===")
        startForeground(NOTIFICATION_ID, buildNotification())

        if (rootView?.parent != null) return

        // 获取屏幕尺寸
        val screenW = resources.displayMetrics.widthPixels
        val screenH = resources.displayMetrics.heightPixels
        Log.d("PetSvc", "screen: ${screenW}x$screenH, density=$density")

        // 小窗边距（dp → px）：左右各 60dp，上 90dp（气泡），下 60dp
        val padH = (60 * density).toInt()
        val padTop = (90 * density).toInt()
        val padBottom = (60 * density).toInt()
        val petW = (120 * density)
        val petH = (120 * density)

        // 创建 PetView — WRAP_CONTENT，onMeasure 决定实际尺寸
        petView = PetView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
            petWidth = petW
            petHeight = petH
            drawPadLeft = padH.toFloat()
            drawPadTop = padTop.toFloat()
            drawPadRight = padH.toFloat()
            drawPadBottom = padBottom.toFloat()

            // 位置变化 → Service 重定位浮窗
            onPositionChanged = { px, py ->
                repositionWindow(px - padH, py - padTop)
            }
            // 用户触摸 → 禁用穿透
            onUserInteraction = {
                if (isPassthrough) setPassthrough(false)
            }
            // 空闲超时 → 启用穿透
            onIdleTimeout = {
                if (!isPassthrough) setPassthrough(true)
            }

            // 触控回调
            onTouchEvent = { type, x, y ->
                Log.d("PetSvc", "touch: $type ($x, $y)")
                when (type) {
                    "tap" -> {
                        // ── Wire 3: 点击宠物 → 弹出迷你聊天 ──
                        // post 延迟：避免 dialog.show() 在触控链内同步创建窗口导致 WindowManager 干扰 PetView 事件处理
                        this@apply.post { showChatDialog() }
                    }
                    else -> touchConsumer?.invoke(type, x, y)
                }
            }
            onPokeCount = { count -> pokeCountConsumer?.invoke(count) }
            onArrive = { x, y -> arriveConsumer?.invoke(x, y) }
        }

        // physics 屏幕坐标系，起始居中偏上
        val startX = (screenW - petW) / 2f
        val startY = screenH * 0.25f
        petView?.physics?.apply {
            x = startX; y = startY
            maxX = screenW.toFloat(); maxY = screenH.toFloat()
            minX = 0f; minY = 0f
        }

        // 加载帧
        loadAllFrames()
        val animNames = petView?.listAnimNames()
        Log.d("PetSvc", "loaded anims: $animNames, screen=${screenW}x$screenH")
        if (animNames?.isNotEmpty() == true) {
            petView?.playAnim("idle")
            Log.d("PetSvc", "playAnim('idle') ok, bmp=${petView?.blender?.currentBitmap()?.width}x${petView?.blender?.currentBitmap()?.height}")
        } else {
            Log.e("PetSvc", "NO ANIMATIONS LOADED — pet will be invisible!")
        }

        // 小窗容器
        rootView = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
            addView(petView)
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        // 默认交互模式（无 FLAG_NOT_TOUCHABLE），小窗不挡屏幕
        val flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS

        windowParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type, flags, PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (startX - padH).toInt()
            y = (startY - padTop).toInt()
        }

        windowManager?.addView(rootView, windowParams)
        isPassthrough = false
        startMonitoring()

        petView?.startRenderLoop()
        petView?.startWandering(screenW, screenH)
        Log.d("PetSvc", "=== showPetWindow v4 COMPLETE ===")
    }

    // ═══════════════════════════════════════════
    // 帧加载 — 优先 Codex spritesheet，回退到文件夹
    // ═══════════════════════════════════════════

    // 旧动画名 → Codex spritesheet 状态名映射（Dart 端仍用旧名时自动转换）
    private val animNameAlias = mapOf(
        "walk" to "run",
        "sit" to "idle",
        "hungry" to "wave",
    )

    private fun loadAllFrames() {
        // ── 方案 A: Codex spritesheet ──
        if (tryLoadSpritesheet()) return

        // ── 方案 B: 回退到旧文件夹格式 ──
        try {
            val allStates = listOf("idle", "walk", "sit", "sleeping", "talking", "hungry")
            for (state in allStates) {
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
                        "walk" -> 80L
                        "sit", "hungry" -> 100L
                        else -> 80L
                    }
                    petView?.registerAnim(state, frames, interval, loop = true)
                    Log.d("PetSvc", "loaded $state: ${frames.size} frames @${interval}ms")
                }
            }

            // 降级：空目录用 idle 帧克隆
            val idleDef = petView?.blender?.getAnim("idle")
            if (idleDef != null && idleDef.frames.isNotEmpty()) {
                for (state in allStates) {
                    if (state == "idle") continue
                    if (!petView!!.listAnimNames().contains(state)) {
                        val interval = when (state) {
                            "sleeping" -> 500L
                            "talking" -> 67L
                            "walk" -> 80L
                            "sit", "hungry" -> 100L
                            else -> 80L
                        }
                        petView?.registerAnim(state, idleDef.frames, interval, loop = true)
                        Log.d("PetSvc", "fallback: $state ← cloned idle ×${idleDef.frames.size} @${interval}ms")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("PetSvc", "loadFrames failed: ${e.message}")
        }
    }

    /**
     * 尝试从 Codex 标准 spritesheet 加载帧。
     * @return true 表示加载成功，无需回退
     */
    private fun tryLoadSpritesheet(): Boolean {
        try {
            // 尝试 .webp 和 .png 两种格式
            val spritesheetPath = listOf("pet_frames/spritesheet.webp", "pet_frames/spritesheet.png")
                .firstOrNull { path ->
                    try { assets.open(path).close(); true }
                    catch (_: Exception) { false }
                } ?: return false

            Log.d("PetSvc", "found spritesheet: $spritesheetPath")
            var stream: InputStream? = null
            try {
                stream = assets.open(spritesheetPath)
                val bmp = BitmapFactory.decodeStream(stream)
                if (bmp == null) return false
                Log.d("PetSvc", "spritesheet decoded: ${bmp.width}×${bmp.height}")

                val loaded = petView?.blender?.loadSpritesheet(bmp) ?: emptySet()
                Log.d("PetSvc", "spritesheet loaded ${loaded.size} anims: $loaded")
                return loaded.isNotEmpty()
            } finally { stream?.close() }
        } catch (e: Exception) {
            Log.e("PetSvc", "spritesheet load failed: ${e.message}")
            return false
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
                var animName = (args?.get("anim") as? String) ?: "idle"
                // 旧动画名 → Codex spritesheet 状态名映射
                animName = animNameAlias[animName] ?: animName
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
                // 预留：Dart 端尚未调用
                pv?.bubble?.hide()
                Log.d("PetSvc", "<<< cmd DONE hideEmoji")
            }
            "setPos" -> {
                val x = (args?.get("x") as? Number)?.toFloat() ?: 100f
                val y = (args?.get("y") as? Number)?.toFloat() ?: 400f
                pv?.physics?.x = x
                pv?.physics?.y = y
                // 小窗跟随
                val padH = pv?.drawPadLeft ?: 0f
                val padTop = pv?.drawPadTop ?: 0f
                repositionWindow(x - padH, y - padTop)
                Log.d("PetSvc", "<<< cmd DONE setPos: ($x, $y)")
            }
            "setSize" -> {
                val w = (args?.get("width") as? Number)?.toFloat() ?: 120f
                val h = (args?.get("height") as? Number)?.toFloat() ?: 120f
                pv?.petWidth = w * density
                pv?.petHeight = h * density
                pv?.requestLayout()  // 触发 onMeasure 重算小窗尺寸
                windowManager?.updateViewLayout(rootView, windowParams)
                Log.d("PetSvc", "<<< cmd DONE setSize: ${(w*density).toInt()}x${(h*density).toInt()}")
            }
            "moveTo" -> {
                val x = (args?.get("x") as? Number)?.toFloat() ?: pv?.physics?.x ?: 100f
                val y = (args?.get("y") as? Number)?.toFloat() ?: pv?.physics?.y ?: 400f
                val speed = (args?.get("speed") as? Number)?.toFloat() ?: 200f
                pv?.moveTo(x, y, speed)
                Log.d("PetSvc", "<<< cmd DONE moveTo: ($x, $y) speed=$speed")
            }
            "setPassthrough" -> {
                // 预留：Dart 端尚未调用（用于拖拽时临时禁用穿透）
                val enabled = args?.get("enabled") as? Boolean ?: false
                setPassthrough(enabled)
                Log.d("PetSvc", "<<< cmd DONE setPassthrough: $enabled")
            }
            "setFacing" -> {
                // 预留：Dart 端尚未调用（用于根据移动方向翻转宠物）
                val left = args?.get("left") as? Boolean ?: false
                pv?.setFacing(left)
                Log.d("PetSvc", "<<< cmd DONE setFacing: left=$left")
            }
            "setFps" -> {
                // 预留：Dart 端尚未调用（用于性能调节）
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

    /** Wire 3: 弹出迷你聊天对话框 — Claymorphism 风格 */
    private fun showChatDialog() {
        val petView = this.petView ?: return
        val ctx = this@PetForegroundService
        val density = resources.displayMetrics.density
        val dp = { n: Int -> (n * density).toInt() }

        // ── 颜色常量（糯糯 Claymorphism 设计系统） ──
        val colorBg = 0xFFFFF7ED.toInt()     // 暖白背景
        val colorPrimary = 0xFFF97316.toInt() // 活力橙
        val colorText = 0xFF9A3412.toInt()     // 深棕文字
        val colorHint = 0xFFD6CCC0.toInt()    // 浅棕 placeholder
        val colorInputBg = 0xFFFFFFFF.toInt() // 输入框白底
        val colorShadow = 0x33000000.toInt()  // 半透明阴影
        val colorCancel = 0xFFB0A090.toInt()  // 取消按钮

        // ── 根容器 ──
        val root = android.widget.FrameLayout(ctx).apply {
            setPadding(dp(20), dp(16), dp(20), dp(16))
            // 圆角背景 + 双阴影（Claymorphism 核心）
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(colorBg)
                cornerRadius = dp(24).toFloat()
                setStroke(dp(3), colorPrimary and 0x33FFFFFF.toInt() or 0xFFFEDDC7.toInt()) // 浅橙厚边框
            }
            // 双阴影：外阴影大而虚 + 内阴影小而实
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                outlineSpotShadowColor = colorPrimary
                elevation = dp(12).toFloat()
            }
        }

        // ── 纵向布局 ──
        val column = android.widget.LinearLayout(ctx).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(dp(8), dp(12), dp(8), dp(8))
        }

        // ── 标题 ──
        val title = android.widget.TextView(ctx).apply {
            text = "💬 和糯糯聊天"
            setTextColor(colorText)
            textSize = 20f
            setTypeface(android.graphics.Typeface.DEFAULT_BOLD)
            setPadding(dp(4), 0, dp(4), dp(12))
        }
        column.addView(title)

        // ── 输入框卡片 ──
        val inputCard = android.widget.FrameLayout(ctx).apply {
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(colorInputBg)
                cornerRadius = dp(16).toFloat()
                setStroke(dp(2), 0xFFFED7B0.toInt()) // 浅橙细边框
            }
            setPadding(dp(4), dp(4), dp(4), dp(4))
        }
        val input = android.widget.EditText(ctx).apply {
            hint = "想对糯糯说什么？"
            setHintTextColor(colorHint)
            setTextColor(colorText)
            textSize = 15f
            setSingleLine(false)
            maxLines = 3
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = null  // 去掉自带下划线
            setLineSpacing(0f, 1.2f)
        }
        inputCard.addView(input)
        column.addView(inputCard)

        // ── 间距 ──
        column.addView(android.widget.Space(ctx).apply { minimumHeight = dp(14) })

        // ── 按钮行 ──
        val btnRow = android.widget.LinearLayout(ctx).apply {
            orientation = android.widget.LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.END
        }

        // 取消按钮
        val cancelBtn = android.widget.TextView(ctx).apply {
            text = "取消"
            setTextColor(colorCancel)
            textSize = 15f
            setPadding(dp(20), dp(10), dp(16), dp(10))
            setOnClickListener {
                dismissChatDialog()
            }
        }
        btnRow.addView(cancelBtn)

        // 发送按钮 — Claymorphism 风格
        val sendBtn = android.widget.TextView(ctx).apply {
            text = "发送 ✦"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 15f
            setTypeface(android.graphics.Typeface.DEFAULT_BOLD)
            setPadding(dp(24), dp(10), dp(24), dp(10))
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(colorPrimary)
                cornerRadius = dp(20).toFloat()
            }
            // 按下缩放反馈（200ms）
            setOnTouchListener { v, event ->
                when (event.action) {
                    android.view.MotionEvent.ACTION_DOWN -> {
                        v.animate().scaleX(0.95f).scaleY(0.95f).setDuration(100).start()
                    }
                    android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                        v.animate().scaleX(1f).scaleY(1f).setDuration(120).start()
                    }
                }
                false
            }
            setOnClickListener {
                val text = input.text.toString().trim()
                if (text.isNotEmpty()) {
                    EngineBridge.invokeMain("chatReq", mapOf(
                        "text" to text,
                        "requestId" to System.currentTimeMillis().toInt(),
                        "history" to emptyList<Map<String, Any>>()
                    ))
                    petView.showBubble(text, 2000)
                }
                dismissChatDialog()
            }
        }
        btnRow.addView(sendBtn)
        column.addView(btnRow)

        root.addView(column)

        // ── 窗口参数 ──
        val type = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O)
            android.view.WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION")
            android.view.WindowManager.LayoutParams.TYPE_PHONE

        val dialogParams = android.view.WindowManager.LayoutParams(
            dp(280),
            android.view.WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            android.view.WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            android.view.WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            android.graphics.PixelFormat.TRANSLUCENT
        ).apply {
            gravity = android.view.Gravity.CENTER
            // 入场动画
            windowAnimations = android.R.style.Animation_Dialog
        }

        // ── 半透明遮罩 ──
        val overlay = android.view.View(ctx).apply {
            setBackgroundColor(0x33000000)
            setOnClickListener { dismissChatDialog() } // 点击遮罩关闭
        }
        val overlayParams = android.view.WindowManager.LayoutParams(
            android.view.WindowManager.LayoutParams.MATCH_PARENT,
            android.view.WindowManager.LayoutParams.MATCH_PARENT,
            type,
            android.view.WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            android.graphics.PixelFormat.TRANSLUCENT
        )

        chatOverlayView = overlay
        chatDialogView = root
        windowManager?.addView(overlay, overlayParams)
        windowManager?.addView(root, dialogParams)
    }

    /** 关闭聊天弹窗 */
    private fun dismissChatDialog() {
        try {
            chatDialogView?.let { windowManager?.removeView(it) }
            chatOverlayView?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {}
        chatDialogView = null
        chatOverlayView = null
    }

    /** 聊天弹窗引用（用于关闭） */
    private var chatDialogView: android.view.View? = null
    private var chatOverlayView: android.view.View? = null

    // ═══════════════════════════════════════════
    // 点击穿透
    // ═══════════════════════════════════════════

    private fun setPassthrough(enabled: Boolean) {
        if (isPassthrough == enabled) return
        isPassthrough = enabled
        val lp = windowParams ?: return
        if (enabled) {
            lp.flags = lp.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        } else {
            lp.flags = lp.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        }
        windowManager?.updateViewLayout(rootView, lp)
        petView?.setPassthrough(enabled)
        Log.d("PetSvc", "setPassthrough: $enabled")
    }

    /** 通知栏"交互"按钮 → 唤醒宠物 */
    private fun enableInteraction() {
        Log.d("PetSvc", "enableInteraction — waking pet")
        setPassthrough(false)
        petView?.resetIdleTimer()
    }

    /** 重定位浮窗到屏幕坐标 (winX, winY) */
    private fun repositionWindow(winX: Float, winY: Float) {
        val lp = windowParams ?: return
        val nx = winX.toInt()
        val ny = winY.toInt()
        if (lp.x != nx || lp.y != ny) {
            lp.x = nx
            lp.y = ny
            windowManager?.updateViewLayout(rootView, lp)
        }
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
        dismissChatDialog()  // 清理聊天弹窗
        hidePetWindow()
        super.onDestroy()
    }
}
