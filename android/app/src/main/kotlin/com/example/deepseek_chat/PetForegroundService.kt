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
                NotificationChannel(CHANNEL_ID, "雪乃电子宠物", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "雪乃正在陪伴你"
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
                .setContentTitle("雪乃").setContentText("雪乃正在陪你...")
                .setSmallIcon(android.R.drawable.ic_dialog_info).setContentIntent(pi)
                .addAction(android.R.drawable.ic_menu_edit, "交互", ipi)
                .addAction(android.R.drawable.ic_media_pause, "关闭", spi).setOngoing(true).build()
        else @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("雪乃").setContentText("雪乃正在陪你...")
                .setSmallIcon(android.R.drawable.ic_dialog_info).setContentIntent(pi).setOngoing(true).build()
    }

    // ═══════════════════════════════════════════
    // 浮窗显示
    // ═══════════════════════════════════════════

    private fun showPetWindow() {
        Log.d("PetSvc", "=== showPetWindow v5 (sprite-sized window) ===")
        startForeground(NOTIFICATION_ID, buildNotification())

        if (rootView?.parent != null) return

        // 获取屏幕尺寸
        val screenW = resources.displayMetrics.widthPixels
        val screenH = resources.displayMetrics.heightPixels
        Log.d("PetSvc", "screen: ${screenW}x$screenH, density=$density")

        val petW = (156 * density)  // 120dp × 1.3
        val petH = (156 * density)

        // 创建 PetView — 窗口大小 = 宠物精灵大小（onMeasure 返回 petW×petH）
        petView = PetView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
            petWidth = petW
            petHeight = petH

            // 位置变化 → Service 重定位浮窗（窗口=精灵，无需 padding 偏移）
            onPositionChanged = { px, py ->
                repositionWindow(px, py)
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
                        // 单击 → 弹出迷你聊天
                        this@apply.post { showChatDialog() }
                    }
                    "doubleTap" -> {
                        // 双击 → 抚摸：跳起 + 爱心粒子
                        petView?.playAnim("jump")
                        petView?.showBubble("💕", 1500)
                        touchConsumer?.invoke("pet", x, y)  // 通知 Dart 加好感+心情
                        Log.d("PetSvc", "doubleTap → petting + affection")
                    }
                    "longPress" -> {
                        // 长按 → 快捷菜单
                        this@apply.post { showQuickMenu(x, y) }
                    }
                    else -> touchConsumer?.invoke(type, x, y)
                }
            }
            onPokeCount = { count -> pokeCountConsumer?.invoke(count) }
            onArrive = { x, y -> arriveConsumer?.invoke(x, y) }
        }

        // physics 屏幕坐标系，起始居中偏上
        // 全屏自由移动——桌面宠物可被拖到屏幕任意位置
        val startX = (screenW - petW) / 2f
        val startY = screenH * 0.25f
        petView?.physics?.apply {
            x = startX; y = startY
            minX = 0f
            maxX = (screenW - petW).toFloat()
            minY = 0f
            maxY = (screenH - petH).toFloat()
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

        // 小窗容器 — clipChildren=false 让气泡能绘制在 PetView 边界之外
        rootView = FrameLayout(this).apply {
            clipChildren = false
            clipToPadding = false
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
            x = startX.toInt()
            y = startY.toInt()
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
                val opts = BitmapFactory.Options().apply {
                    inPreferredConfig = Bitmap.Config.ARGB_8888  // 保留 alpha 通道
                }
                val bmp = BitmapFactory.decodeStream(stream, null, opts)
                if (bmp == null) {
                    Log.e("PetSvc", "spritesheet decode FAILED — BitmapFactory returned null")
                    return false
                }
                Log.d("PetSvc", "spritesheet decoded: ${bmp.width}×${bmp.height}, cells=${bmp.width/FrameBlender.SPRITESHEET_COLS}×${bmp.height/FrameBlender.SPRITESHEET_ROWS}")

                val loaded = petView?.blender?.loadSpritesheet(bmp) ?: emptySet()
                Log.d("PetSvc", "spritesheet loaded ${loaded.size} anims: $loaded")
                if (loaded.isEmpty()) {
                    Log.e("PetSvc", "spritesheet load returned 0 anims — wrong dimensions? w/8=${bmp.width/8} h/9=${bmp.height/9}")
                }
                return loaded.isNotEmpty()
            } finally { stream?.close() }
        } catch (e: Exception) {
            Log.e("PetSvc", "spritesheet load failed: ${e.message}", e)
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
            // ── 聊天流式响应 → 更新 Dialog 消息列表 ──
            "chatChunk" -> {
                val text = (args?.get("text") as? String) ?: ""
                val isStreaming = args?.get("isStreaming") as? Boolean ?: true
                val rid = (args?.get("requestId") as? Number)?.toInt() ?: 0
                updateChatDialog(rid, text, isStreaming, null)
                Log.d("PetSvc", "<<< cmd DONE chatChunk: len=${text.length}")
            }
            "chatDone" -> {
                val rid = (args?.get("requestId") as? Number)?.toInt() ?: 0
                updateChatDialog(rid, null, false, true)
                Log.d("PetSvc", "<<< cmd DONE chatDone")
            }
            "chatError" -> {
                val msg = (args?.get("message") as? String) ?: "出错了喵..."
                val rid = (args?.get("requestId") as? Number)?.toInt() ?: 0
                updateChatDialog(rid, msg, false, false)
                Log.d("PetSvc", "<<< cmd DONE chatError")
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
                // 窗口=精灵大小，直接跟随
                repositionWindow(x, y)
                Log.d("PetSvc", "<<< cmd DONE setPos: ($x, $y)")
            }
            "setSize" -> {
                val w = (args?.get("width") as? Number)?.toFloat() ?: 156f
                val h = (args?.get("height") as? Number)?.toFloat() ?: 156f
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

    /** Wire 3: 弹出迷你聊天对话框 — 含完整对话历史 + 流式响应 + 空闲自动关闭 */
    private fun showChatDialog() {
        val petView = this.petView ?: return
        val ctx = this@PetForegroundService
        val density = resources.displayMetrics.density
        val dp = { n: Int -> (n * density).toInt() }

        // ── 颜色常量 ──
        val colorBg = 0xFF212124.toInt()
        val colorCard = 0xFF2E2E32.toInt()
        val colorBorder = 0xFF3A3A3E.toInt()
        val colorAccent = 0xFFB8935D.toInt()
        val colorText = 0xFFE4DFD8.toInt()
        val colorHint = 0xFF5E5A54.toInt()
        val colorInputBg = 0xFF28282C.toInt()
        val colorUserBubble = 0xFF3D3524.toInt()
        val colorUserBorder = 0xFFB8935D.toInt()

        // 重置状态
        chatMessages.clear()
        chatRequestId = System.currentTimeMillis().toInt()
        chatIdleTimer?.cancel()

        // 获取状态栏高度
        val statusBarH = resources.getIdentifier("status_bar_height", "dimen", "android")
            .takeIf { it > 0 }?.let { resources.getDimensionPixelSize(it) } ?: dp(24)

        // ── 根容器 ──
        val root = android.widget.FrameLayout(ctx).apply {
            setPadding(dp(16), dp(16), dp(16), dp(12))
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(colorBg)
                cornerRadius = dp(14).toFloat()
                setStroke(dp(1), colorBorder)
            }
            elevation = dp(12).toFloat()
        }

        // ── 主列：header(fixed) + body(scrollable) + input(fixed) ──
        val column = android.widget.LinearLayout(ctx).apply {
            orientation = android.widget.LinearLayout.VERTICAL
        }

        // ── 标题栏（固定）──
        val header = android.widget.LinearLayout(ctx).apply {
            orientation = android.widget.LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
            setPadding(dp(4), 0, dp(4), dp(10))
        }
        val title = android.widget.TextView(ctx).apply {
            text = "和雪乃聊天"
            setTextColor(colorText)
            textSize = 15f
            setTypeface(android.graphics.Typeface.DEFAULT_BOLD)
        }
        header.addView(title)
        header.addView(android.widget.Space(ctx).apply { layoutParams = android.widget.LinearLayout.LayoutParams(0, 1, 1f) })
        // ── 新建对话按钮 ──
        val newChatBtn = android.widget.TextView(ctx).apply {
            text = "+"
            setTextColor(colorAccent)
            textSize = 20f
            setTypeface(android.graphics.Typeface.DEFAULT_BOLD)
            setPadding(dp(8), dp(2), dp(8), dp(4))
            setOnClickListener {
                // 保存当前会话 → 创建新会话 → 清空界面
                saveChatHistory()
                chatMessages.clear()
                val newId = createPopupSession()
                currentChatSessionId = newId
                // 清空消息列表 UI（使用类字段，避免前向引用编译错误）
                chatMsgContainer?.removeAllViews()
                chatWelcomeHint?.let { hint ->
                    chatMsgContainer?.addView(hint)
                    hint.visibility = android.view.View.VISIBLE
                }
                // 隐藏加载指示器
                chatLoadingView?.visibility = android.view.View.GONE
                // 聚焦输入框
                chatInput?.requestFocus()
                Log.d("PetSvc", "new popup chat session: $newId")
            }
        }
        header.addView(newChatBtn)
        val closeBtn = android.widget.TextView(ctx).apply {
            text = "✕"
            setTextColor(colorHint)
            textSize = 18f
            setPadding(dp(8), dp(4), 0, dp(4))
            setOnClickListener { dismissChatDialog() }
        }
        header.addView(closeBtn)
        column.addView(header)

        // ── 消息列表 (ScrollView > LinearLayout) ──
        val scrollView = android.widget.ScrollView(ctx).apply {
            layoutParams = android.widget.LinearLayout.LayoutParams(
                dp(280), 0, 1f  // weight=1 填满剩余空间
            )
            setPadding(0, 0, 0, dp(4))
            setVerticalScrollBarEnabled(false)
        }
        val msgContainer = android.widget.LinearLayout(ctx).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(dp(4), 0, dp(4), 0)
        }
        val welcomeHint = android.widget.TextView(ctx).apply {
            text = "和雪乃聊聊吧~ 💬"
            setTextColor(colorHint)
            textSize = 12f
            gravity = android.view.Gravity.CENTER
            setPadding(0, dp(20), 0, dp(20))
        }
        msgContainer.addView(welcomeHint)
        scrollView.addView(msgContainer)
        column.addView(scrollView)

        // ── 加载指示器（默认隐藏）──
        val loadingRow = android.widget.LinearLayout(ctx).apply {
            orientation = android.widget.LinearLayout.HORIZONTAL
            setPadding(dp(12), dp(4), 0, dp(4))
            gravity = android.view.Gravity.CENTER_VERTICAL
            visibility = android.view.View.GONE
        }
        val loadingDots = android.widget.TextView(ctx).apply {
            text = "● ● ●"
            setTextColor(colorAccent)
            textSize = 10f
            setPadding(0, 0, dp(6), 0)
        }
        val loadingLabel = android.widget.TextView(ctx).apply {
            text = "雪乃思考中..."
            setTextColor(colorHint)
            textSize = 12f
        }
        loadingRow.addView(loadingDots)
        loadingRow.addView(loadingLabel)
        column.addView(loadingRow)

        // 加载动画：文字透明度呼吸 0.35 → 1.0
        loadingAnimator = android.animation.ValueAnimator.ofFloat(0.35f, 1.0f).apply {
            duration = 800
            repeatMode = android.animation.ValueAnimator.REVERSE
            repeatCount = android.animation.ValueAnimator.INFINITE
            addUpdateListener { anim ->
                val alpha = anim.animatedValue as Float
                loadingDots.alpha = alpha
                loadingLabel.alpha = alpha
            }
        }

        // ── 输入区（固定）──
        val inputRow = android.widget.LinearLayout(ctx).apply {
            orientation = android.widget.LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
            setPadding(0, dp(8), 0, 0)
        }
        val input = android.widget.EditText(ctx).apply {
            hint = "想说点什么？"
            setHintTextColor(colorHint)
            setTextColor(colorText)
            textSize = 13f
            setSingleLine(true)
            setPadding(dp(12), dp(10), dp(12), dp(10))
            // 显式设置光标颜色（Android 9+ 通过 textCursorDrawable 控制）
            try {
                val cursorField = android.widget.TextView::class.java.getDeclaredField("mCursorDrawableRes")
                cursorField.isAccessible = true
                cursorField.set(this, 0)  // 0 = 使用 textColor 作为光标色
            } catch (_: Exception) {}
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(colorInputBg)
                cornerRadius = dp(8).toFloat()
                setStroke(dp(1), colorBorder)
            }
            layoutParams = android.widget.LinearLayout.LayoutParams(0, android.view.ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            setOnFocusChangeListener { _, hasFocus ->
                if (hasFocus) resetChatIdleTimer()
            }
            setOnClickListener { resetChatIdleTimer() }
            // 每次输入文字都重置空闲计时——防止打字打到一半键盘被收走
            addTextChangedListener(object : android.text.TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    resetChatIdleTimer()
                }
                override fun afterTextChanged(s: android.text.Editable?) {}
            })
        }
        inputRow.addView(input)

        val sendBtn = android.widget.TextView(ctx).apply {
            text = "发送"
            setTextColor(0xFF212124.toInt())
            textSize = 13f
            setTypeface(android.graphics.Typeface.DEFAULT_BOLD)
            setPadding(dp(16), dp(10), dp(16), dp(10))
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(colorAccent)
                cornerRadius = dp(8).toFloat()
            }
            // 按下反馈
            setOnTouchListener { v, event ->
                when (event.action) {
                    android.view.MotionEvent.ACTION_DOWN -> v.alpha = 0.7f
                    android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> v.alpha = 1f
                }
                false
            }
            setOnClickListener { sendChatMessage(input, ctx, dp, colorText, colorUserBubble, colorUserBorder, colorCard, colorBorder, colorAccent, colorHint, scrollView, msgContainer, welcomeHint, loadingRow, petView) }
        }
        inputRow.addView(sendBtn)
        column.addView(inputRow)

        root.addView(column)

        // ── 保存引用 ──
        chatMsgContainer = msgContainer
        chatScrollView = scrollView
        chatInput = input
        chatLoadingView = loadingRow
        chatWelcomeHint = welcomeHint
        chatDialogView = root

        // ── 加载历史消息 ──
        ensureSessionIndex()
        loadChatHistory(msgContainer, dp, colorUserBubble, colorUserBorder, colorCard, colorBorder, colorAccent, colorHint, welcomeHint)

        // ── 窗口参数 ──
        val type = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O)
            android.view.WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION")
            android.view.WindowManager.LayoutParams.TYPE_PHONE

        val screenH = resources.displayMetrics.heightPixels
        // 弹窗紧贴状态栏下方，高度自适应（最多 420dp），确保在任何屏幕上都完整可见
        val dialogMaxH = minOf(dp(420), screenH - statusBarH - dp(40))  // 底部留 40dp 给键盘区域

        val dialogParams = android.view.WindowManager.LayoutParams(
            dp(300),
            dialogMaxH,
            type,
            android.view.WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            android.view.WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            android.graphics.PixelFormat.TRANSLUCENT
        ).apply {
            gravity = android.view.Gravity.TOP or android.view.Gravity.CENTER_HORIZONTAL
            y = statusBarH
            windowAnimations = android.R.style.Animation_Dialog
        }

        // ── 半透明遮罩 ──
        val overlay = android.view.View(ctx).apply {
            setBackgroundColor(0x44000000)
            setOnClickListener { dismissChatDialog() }
        }
        val overlayParams = android.view.WindowManager.LayoutParams(
            android.view.WindowManager.LayoutParams.MATCH_PARENT,
            android.view.WindowManager.LayoutParams.MATCH_PARENT,
            type,
            android.view.WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            android.graphics.PixelFormat.TRANSLUCENT
        )

        chatOverlayView = overlay
        windowManager?.addView(overlay, overlayParams)
        windowManager?.addView(root, dialogParams)

        // ── 入场动画：遮罩淡入 + 弹窗缩放 ──
        overlay.alpha = 0f
        overlay.animate().alpha(1f).setDuration(250).setInterpolator(
            android.view.animation.DecelerateInterpolator()
        ).start()
        root.scaleX = 0.9f; root.scaleY = 0.9f; root.alpha = 0f
        root.animate()
            .scaleX(1f).scaleY(1f).alpha(1f)
            .setDuration(300)
            .setInterpolator(android.view.animation.OvershootInterpolator(0.6f))
            .start()

        // 聚焦输入框
        input.postDelayed({
            input.requestFocus()
            val imm = getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as? android.view.inputmethod.InputMethodManager
            imm?.showSoftInput(input, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
        }, 200)
    }

    /** 发送聊天消息 */
    private fun sendChatMessage(
        input: android.widget.EditText,
        ctx: android.content.Context,
        dp: (Int) -> Int,
        colorText: Int,
        colorUserBubble: Int,
        colorUserBorder: Int,
        colorCard: Int,
        colorBorder: Int,
        colorAccent: Int,
        colorHint: Int,
        scrollView: android.widget.ScrollView,
        msgContainer: android.widget.LinearLayout,
        welcomeHint: android.widget.TextView,
        loadingRow: android.widget.LinearLayout,
        petView: PetView
    ) {
        val text = input.text.toString().trim()
        if (text.isEmpty()) return

        // 隐藏欢迎提示
        welcomeHint.visibility = android.view.View.GONE
        // 添加用户消息气泡
        addChatBubble(msgContainer, true, text, colorUserBubble, colorUserBorder, dp)
        input.text.clear()

        // 显示加载指示器
        loadingRow.visibility = android.view.View.VISIBLE
        loadingAnimator?.start()
        scrollView.postDelayed({
            scrollView.fullScroll(android.view.View.FOCUS_DOWN)
        }, 100)

        // 发送到 Flutter
        chatRequestId = System.currentTimeMillis().toInt()
        chatMessages.add(ChatMsg(true, text))
        // 预留 AI 消息槽位
        chatMessages.add(ChatMsg(false, "", true))

        // 构建历史上下文（排除当前轮的空 AI 槽位）
        val historyList = mutableListOf<Map<String, Any>>()
        for (i in 0 until chatMessages.size - 2) {
            val m = chatMessages[i]
            if (m.text.isNotEmpty()) {
                historyList.add(mapOf("role" to if (m.isUser) "user" else "assistant", "content" to m.text))
            }
        }
        EngineBridge.invokeMain("chatReq", mapOf(
            "text" to text,
            "requestId" to chatRequestId,
            "history" to historyList
        ))

        // 重置空闲计时
        resetChatIdleTimer()
    }

    /** 添加聊天气泡到消息容器 */
    private fun addChatBubble(
        container: android.widget.LinearLayout,
        isUser: Boolean,
        text: String,
        userBg: Int,
        userBorder: Int,
        dp: (Int) -> Int
    ) {
        val ctx = this@PetForegroundService
        val colorText = 0xFFE4DFD8.toInt()
        val colorCard = 0xFF2E2E32.toInt()
        val colorBorder = 0xFF3A3A3E.toInt()
        val colorAccent = 0xFFB8935D.toInt()
        val colorHint = 0xFF8B857D.toInt()

        // 气泡容器
        val bubbleRow = android.widget.LinearLayout(ctx).apply {
            orientation = android.widget.LinearLayout.HORIZONTAL
            gravity = if (isUser) android.view.Gravity.END else android.view.Gravity.START
            setPadding(0, dp(3), 0, dp(3))
        }

        // 间隔
        if (!isUser) {
            bubbleRow.addView(android.widget.Space(ctx).apply {
                layoutParams = android.widget.LinearLayout.LayoutParams(dp(4), 1)
            })
        }

        val bubble = android.widget.TextView(ctx).apply {
            this.text = text
            setTextColor(if (isUser) colorText else colorText)
            textSize = 13f
            setPadding(dp(10), dp(7), dp(10), dp(7))
            maxWidth = dp(200)
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(if (isUser) 0xFF3D3524.toInt() else colorCard)
                cornerRadius = dp(10).toFloat()
                setStroke(dp(1), if (isUser) colorAccent else colorBorder)
            }
        }
        bubbleRow.addView(bubble)

        if (isUser) {
            bubbleRow.addView(android.widget.Space(ctx).apply {
                layoutParams = android.widget.LinearLayout.LayoutParams(dp(4), 1)
            })
        }

        container.addView(bubbleRow)
    }

    /** 更新聊天 Dialog 中的 AI 回复（流式 / 完成 / 错误） */
    private fun updateChatDialog(rid: Int, chunkText: String?, isStreaming: Boolean, doneOrNull: Boolean?) {
        val container = chatMsgContainer ?: return
        val scrollView = chatScrollView ?: return
        val loadingRow = chatLoadingView ?: return

        // chatDone / chatError → 隐藏加载指示器
        if (doneOrNull != null) {
            loadingRow.visibility = android.view.View.GONE
            loadingAnimator?.cancel()
        }

        // 更新最后一条 AI 消息
        val lastIdx = chatMessages.indexOfLast { !it.isUser }
        if (lastIdx >= 0) {
            val newText: String = when {
                doneOrNull == false -> chunkText ?: "出错了喵..."
                chunkText != null -> chunkText
                else -> chatMessages[lastIdx].text
            }
            chatMessages[lastIdx] = ChatMsg(false, newText, isStreaming)
        }

        // 重建消息列表（简化实现：清空重建）
        val dp = { n: Int -> (n * resources.displayMetrics.density).toInt() }
        val userBg = 0xFF3D3524.toInt()
        val userBorder = 0xFFB8935D.toInt()

        // 只重建 AI 消息部分（最后一条），不重建全部（避免闪烁）
        // 计算当前 AI 消息在容器中的位置
        var msgViewIndex = -1
        for (i in 0 until container.childCount) {
            val child = container.getChildAt(i)
            // user bubbles have a space on the right, AI bubbles have a space on the left
            // 我们通过 tag 来识别
            if (child.tag == "ai_msg_$rid" || (child.tag == null && i > 0)) {
                msgViewIndex = i
            }
        }

        // 移除旧的 AI 流式消息并添加新的
        val aiViewTag = "ai_msg_$rid"
        val oldAiView = container.findViewWithTag<android.view.View>(aiViewTag)
        oldAiView?.let { container.removeView(it) }

        if (chatMessages.isNotEmpty()) {
            val lastMsg = chatMessages.last()
            if (!lastMsg.isUser) {
                val bubbleRow = android.widget.LinearLayout(this).apply {
                    orientation = android.widget.LinearLayout.HORIZONTAL
                    gravity = android.view.Gravity.START
                    setPadding(0, dp(3), 0, dp(3))
                    tag = aiViewTag
                }
                bubbleRow.addView(android.widget.Space(this).apply {
                    layoutParams = android.widget.LinearLayout.LayoutParams(dp(4), 1)
                })
                val bubble = android.widget.TextView(this).apply {
                    text = lastMsg.text
                    setTextColor(0xFFE4DFD8.toInt())
                    textSize = 13f
                    setPadding(dp(10), dp(7), dp(10), dp(7))
                    maxWidth = dp(200)
                    background = android.graphics.drawable.GradientDrawable().apply {
                        setColor(0xFF2E2E32.toInt())
                        cornerRadius = dp(10).toFloat()
                        setStroke(dp(1), 0xFF3A3A3E.toInt())
                    }
                }
                bubbleRow.addView(bubble)
                container.addView(bubbleRow)

                // 流式完成时添加反馈按钮
                if (doneOrNull == true && lastMsg.text.isNotEmpty()) {
                    val fbRow = android.widget.LinearLayout(this).apply {
                        orientation = android.widget.LinearLayout.HORIZONTAL
                        setPadding(dp(8), dp(2), 0, dp(6))
                        gravity = android.view.Gravity.START
                    }
                    val likeBtn = android.widget.TextView(this).apply {
                        text = "👍"
                        textSize = 14f
                        setPadding(0, 0, dp(12), 0)
                        setOnClickListener {
                            EngineBridge.invokeMain("feedback", mapOf("liked" to true))
                            this.text = "👍 ✓"
                            it.isEnabled = false
                            (fbRow.getChildAt(1) as? android.widget.TextView)?.isEnabled = false
                        }
                    }
                    val dislikeBtn = android.widget.TextView(this).apply {
                        text = "👎"
                        textSize = 14f
                        setOnClickListener {
                            EngineBridge.invokeMain("feedback", mapOf("liked" to false))
                            this.text = "👎 ✓"
                            it.isEnabled = false
                            (fbRow.getChildAt(0) as? android.widget.TextView)?.isEnabled = false
                        }
                    }
                    fbRow.addView(likeBtn)
                    fbRow.addView(dislikeBtn)
                    container.addView(fbRow)
                }
            }
        }

        // 滚动到底部
        scrollView.postDelayed({
            scrollView.fullScroll(android.view.View.FOCUS_DOWN)
        }, 100)

        // 流式完成 → 立即持久化 + 启动空闲自动关闭计时
        if (doneOrNull == true) {
            saveChatHistory()  // 防止进程被杀死丢失本轮对话
            resetChatIdleTimer()
        }
    }

    /** 重置空闲关闭计时器（5 秒无交互自动关闭） */
    private fun resetChatIdleTimer() {
        chatIdleTimer?.cancel()
        chatIdleTimer = java.util.Timer().apply {
            schedule(object : java.util.TimerTask() {
                override fun run() {
                    val imm = getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as? android.view.inputmethod.InputMethodManager
                    chatInput?.let { imm?.hideSoftInputFromWindow(it.windowToken, 0) }
                    android.os.Handler(mainLooper).post { dismissChatDialog() }
                }
            }, 5000)
        }
    }

    /** 关闭聊天弹窗 */
    private fun dismissChatDialog() {
        chatIdleTimer?.cancel()
        chatIdleTimer = null
        loadingAnimator?.cancel()
        loadingAnimator = null
        // 持久化当前聊天记录
        saveChatHistory()
        try {
            chatDialogView?.let { windowManager?.removeView(it) }
            chatOverlayView?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {}
        chatDialogView = null
        chatOverlayView = null
        chatMsgContainer = null
        chatScrollView = null
        chatInput = null
        chatLoadingView = null
        chatWelcomeHint = null
        chatMessages.clear()
        currentChatSessionId = null
    }

    /** 加载上一次的聊天历史到消息列表 */
    private fun loadChatHistory(
        container: android.widget.LinearLayout,
        dp: (Int) -> Int,
        userBg: Int, userBorder: Int,
        cardBg: Int, border: Int,
        accent: Int, hint: Int,
        welcomeHint: android.widget.TextView
    ) {
        try {
            val prefs = getSharedPreferences("pet_chat", android.content.Context.MODE_PRIVATE)
            val sessionId = prefs.getString("last_session_id", null) ?: return
            val msgCount = prefs.getInt("msg_count_$sessionId", 0)
            if (msgCount == 0) return

            currentChatSessionId = sessionId
            welcomeHint.visibility = android.view.View.GONE

            for (i in 0 until msgCount) {
                val isUser = prefs.getBoolean("msg_${sessionId}_${i}_isUser", false)
                val text = prefs.getString("msg_${sessionId}_${i}_text", "") ?: ""
                if (text.isNotEmpty()) {
                    addChatBubble(container, isUser, text, userBg, userBorder, dp)
                    chatMessages.add(ChatMsg(isUser, text, false))
                }
            }
            Log.d("PetSvc", "loaded $msgCount history messages, session=$sessionId")
        } catch (e: Exception) {
            Log.e("PetSvc", "loadChatHistory failed: ${e.message}")
        }
    }

    /** 获取弹窗聊天历史（供 Flutter 侧 MethodChannel 调用） */
    fun getPopupHistory(): List<Map<String, Any>> {
        try {
            if (chatMessages.isNotEmpty()) return chatMessages.map { mapOf("isUser" to it.isUser, "text" to it.text) }
            val prefs = getSharedPreferences("pet_chat", android.content.Context.MODE_PRIVATE)
            val sessionId = prefs.getString("last_session_id", null) ?: return emptyList()
            val msgCount = prefs.getInt("msg_count_$sessionId", 0)
            val result = mutableListOf<Map<String, Any>>()
            for (i in 0 until msgCount) {
                val isUser = prefs.getBoolean("msg_${sessionId}_${i}_isUser", false)
                val text = prefs.getString("msg_${sessionId}_${i}_text", "") ?: ""
                if (text.isNotEmpty()) result.add(mapOf("isUser" to isUser, "text" to text))
            }
            return result
        } catch (e: Exception) { return emptyList() }
    }

    /** 清除弹窗聊天历史（供 Flutter 侧 MethodChannel 调用） */
    fun clearPopupHistory() {
        try {
            val prefs = getSharedPreferences("pet_chat", android.content.Context.MODE_PRIVATE)
            val sessionId = currentChatSessionId ?: prefs.getString("last_session_id", null)
            if (sessionId != null) {
                deletePopupSession(sessionId)
            }
            chatMessages.clear(); currentChatSessionId = null
        } catch (_: Exception) {}
    }

    // ═══════════════════════════════════════════
    // 多会话管理（会话索引 CRUD）
    // ═══════════════════════════════════════════

    /**
     * 弹窗会话存储 — 纯 SharedPreferences 操作，不依赖 Service 实例。
     * MainActivity 在服务未运行时直接用此类操作数据，确保创建/删除/切换等功能始终可用。
     */
    object PopupSessionStore {
        private const val PREFS_NAME = "pet_chat"
        private fun prefs(ctx: android.content.Context) = ctx.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)

        /** 安全构建 JSONArray——逐个 put JSONObject，避免 JSONArray(Collection) 把字符串当纯文本 */
        fun toJSONArray(maps: List<Map<String, Any?>>): org.json.JSONArray {
            val arr = org.json.JSONArray()
            for (map in maps) {
                val obj = org.json.JSONObject()
                for ((k, v) in map) { if (v != null) obj.put(k, v) }
                arr.put(obj)
            }
            return arr
        }

        /** 从可能损坏的 JSON 字符串安全解析 JSONArray，检测到旧版格式时自动修复 SP */
        fun parseSessionsArray(raw: String, ctx: android.content.Context? = null): org.json.JSONArray {
            return try {
                val arr = org.json.JSONArray(raw)
                // 检测是否旧版损坏格式（数组元素是 String 而非 JSONObject）
                if (arr.length() > 0) {
                    try { arr.getJSONObject(0) }
                    catch (_: org.json.JSONException) {
                        // 迁移：字符串数组 → 对象数组
                        val fixed = org.json.JSONArray()
                        for (i in 0 until arr.length()) {
                            try { fixed.put(org.json.JSONObject(arr.getString(i))) }
                            catch (_: Exception) {}
                        }
                        // 自动写回正确格式
                        if (ctx != null) {
                            prefs(ctx).edit().putString("popup_sessions", fixed.toString()).apply()
                            Log.d("PopupStore", "auto-repaired corrupted popup_sessions (${fixed.length()} sessions)")
                        }
                        return fixed
                    }
                }
                arr
            } catch (_: Exception) {
                org.json.JSONArray()
            }
        }

        private fun ensureIndex(ctx: android.content.Context) {
            val p = prefs(ctx)
            if (p.contains("popup_sessions")) return
            val lastId = p.getString("last_session_id", null) ?: return
            val msgCount = p.getInt("msg_count_$lastId", 0)
            if (msgCount == 0) return
            var title = "旧对话"
            for (i in 0 until msgCount) {
                if (p.getBoolean("msg_${lastId}_${i}_isUser", false)) {
                    val t = p.getString("msg_${lastId}_${i}_text", "") ?: ""
                    if (t.isNotEmpty()) { title = if (t.length <= 20) t else t.substring(0, 20) + "..."; break }
                }
            }
            val arr = toJSONArray(listOf(mapOf(
                "id" to lastId, "title" to title,
                "createdAt" to (lastId.toLongOrNull() ?: System.currentTimeMillis()),
                "msgCount" to msgCount
            )))
            p.edit().putString("popup_sessions", arr.toString()).apply()
        }

        private fun updateMeta(ctx: android.content.Context, id: String, title: String?, msgCount: Int) {
            try {
                val p = prefs(ctx)
                val raw = p.getString("popup_sessions", null) ?: "[]"
                val arr = parseSessionsArray(raw, ctx)
                val now = System.currentTimeMillis()
                var found = false
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    if (obj.getString("id") == id) {
                        found = true
                        if (title != null) obj.put("title", title)
                        obj.put("msgCount", msgCount)
                    }
                }
                if (!found) {
                    arr.put(org.json.JSONObject().apply {
                        put("id", id); put("title", title ?: "新对话")
                        put("createdAt", id.toLongOrNull() ?: now); put("msgCount", msgCount)
                    })
                }
                // 按 createdAt 降序重建
                val sorted = (0 until arr.length()).map { i ->
                    val obj = arr.getJSONObject(i)
                    (0 until obj.length()).associate { k -> obj.keys().next() to obj.get(obj.keys().next()) }
                }.sortedByDescending { (it["createdAt"] as? Long) ?: 0L }
                p.edit().putString("popup_sessions", toJSONArray(sorted).toString()).apply()
            } catch (e: Exception) {
                Log.e("PopupStore", "updateMeta failed: ${e.message}")
            }
        }

        fun listSessions(ctx: android.content.Context): List<Map<String, Any>> {
            try {
                ensureIndex(ctx)
                val p = prefs(ctx)
                val raw = p.getString("popup_sessions", null) ?: return emptyList()
                val arr = parseSessionsArray(raw, ctx)
                val result = mutableListOf<Map<String, Any>>()
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    result.add(mapOf(
                        "id" to obj.getString("id"),
                        "title" to (obj.optString("title", "新对话")),
                        "createdAt" to obj.optLong("createdAt", 0L),
                        "msgCount" to obj.optInt("msgCount", 0)
                    ))
                }
                return result
            } catch (e: Exception) { return emptyList() }
        }

        fun createSession(ctx: android.content.Context): String {
            val id = System.currentTimeMillis().toString()
            prefs(ctx).edit().putString("last_session_id", id).apply()
            ensureIndex(ctx)
            updateMeta(ctx, id, "新对话", 0)
            return id
        }

        fun deleteSession(ctx: android.content.Context, sessionId: String) {
            try {
                val p = prefs(ctx)
                val editor = p.edit()
                val msgCount = p.getInt("msg_count_$sessionId", 0)
                for (i in 0 until msgCount) {
                    editor.remove("msg_${sessionId}_${i}_isUser")
                    editor.remove("msg_${sessionId}_${i}_text")
                }
                editor.remove("msg_count_$sessionId").apply()

                val raw = p.getString("popup_sessions", null) ?: "[]"
                val arr = parseSessionsArray(raw, ctx)
                // 过滤掉被删除的 session，保留为 JSONObject
                val kept = (0 until arr.length()).mapNotNull { i ->
                    val obj = arr.getJSONObject(i)
                    if (obj.getString("id") != sessionId) obj else null
                }
                // 重建数组
                val newArr = org.json.JSONArray()
                kept.forEach { newArr.put(it) }
                p.edit().putString("popup_sessions", newArr.toString()).apply()

                val lastId = p.getString("last_session_id", null)
                if (lastId == sessionId) {
                    val sessions = listSessions(ctx)
                    if (sessions.isNotEmpty()) p.edit().putString("last_session_id", sessions.first()["id"] as String).apply()
                    else p.edit().remove("last_session_id").apply()
                }
                Log.d("PopupStore", "session deleted: $sessionId ($msgCount msgs)")
            } catch (e: Exception) {
                Log.e("PopupStore", "deleteSession failed: ${e.message}")
            }
        }

        fun switchSession(ctx: android.content.Context, sessionId: String) {
            prefs(ctx).edit().putString("last_session_id", sessionId).apply()
        }

        fun getMessages(ctx: android.content.Context, sessionId: String?): List<Map<String, Any>> {
            try {
                val p = prefs(ctx)
                val sid = sessionId ?: p.getString("last_session_id", null) ?: return emptyList()
                val msgCount = p.getInt("msg_count_$sid", 0)
                val result = mutableListOf<Map<String, Any>>()
                for (i in 0 until msgCount) {
                    val isUser = p.getBoolean("msg_${sid}_${i}_isUser", false)
                    val text = p.getString("msg_${sid}_${i}_text", "") ?: ""
                    if (text.isNotEmpty()) result.add(mapOf("isUser" to isUser, "text" to text))
                }
                return result
            } catch (e: Exception) { return emptyList() }
        }

        fun saveMessage(ctx: android.content.Context, sessionId: String, isUser: Boolean, text: String) {
            try {
                val p = prefs(ctx)
                val msgCount = p.getInt("msg_count_$sessionId", 0)
                p.edit()
                    .putBoolean("msg_${sessionId}_${msgCount}_isUser", isUser)
                    .putString("msg_${sessionId}_${msgCount}_text", text)
                    .putInt("msg_count_$sessionId", msgCount + 1)
                    .putString("last_session_id", sessionId)
                    .apply()
                ensureIndex(ctx)
                val title = if (isUser) (if (text.length <= 20) text else text.substring(0, 20) + "...") else null
                updateMeta(ctx, sessionId, title, msgCount + 1)
            } catch (e: Exception) {
                Log.e("PopupStore", "saveMessage failed: ${e.message}")
            }
        }
    }

    /** 会话索引记录 */
    private data class PopupSessionMeta(
        val id: String,
        var title: String,
        val createdAt: Long,
        var msgCount: Int
    )

    /** 确保会话索引存在（数据迁移：旧版无 popup_sessions 时从 msg_* 重建） */
    private fun ensureSessionIndex() {
        val prefs = getSharedPreferences("pet_chat", android.content.Context.MODE_PRIVATE)
        if (prefs.contains("popup_sessions")) return // 索引已存在

        val lastId = prefs.getString("last_session_id", null) ?: return
        val msgCount = prefs.getInt("msg_count_$lastId", 0)
        if (msgCount == 0) return

        // 从首条用户消息提取标题
        var title = "旧对话"
        for (i in 0 until msgCount) {
            if (prefs.getBoolean("msg_${lastId}_${i}_isUser", false)) {
                val text = prefs.getString("msg_${lastId}_${i}_text", "") ?: ""
                if (text.isNotEmpty()) {
                    title = if (text.length <= 20) text else text.substring(0, 20) + "..."
                    break
                }
            }
        }

        val arr = PopupSessionStore.toJSONArray(listOf(mapOf(
            "id" to lastId, "title" to title,
            "createdAt" to (lastId.toLongOrNull() ?: System.currentTimeMillis()),
            "msgCount" to msgCount
        )))
        prefs.edit().putString("popup_sessions", arr.toString()).apply()
        Log.d("PetSvc", "session index migrated: $lastId ($msgCount msgs)")
    }

    /** 更新会话索引中的单条记录 */
    private fun updateSessionMeta(id: String, title: String?, msgCount: Int) {
        try {
            val prefs = getSharedPreferences("pet_chat", android.content.Context.MODE_PRIVATE)
            val raw = prefs.getString("popup_sessions", null) ?: "[]"
            val arr = PopupSessionStore.parseSessionsArray(raw, this)
            val now = System.currentTimeMillis()

            // 查找已有记录并更新
            var found = false
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                if (obj.getString("id") == id) {
                    found = true
                    if (title != null) obj.put("title", title)
                    obj.put("msgCount", msgCount)
                }
            }

            if (!found) {
                // 新会话：追加到索引
                arr.put(org.json.JSONObject().apply {
                    put("id", id); put("title", title ?: "新对话")
                    put("createdAt", id.toLongOrNull() ?: now); put("msgCount", msgCount)
                })
            }

            // 转 Map 排序 → 重建
            val sessions = (0 until arr.length()).map { i ->
                val obj = arr.getJSONObject(i)
                (0 until obj.length()).associate { k -> obj.keys().next() to obj.get(obj.keys().next()) }
            }.sortedByDescending { (it["createdAt"] as? Long) ?: 0L }
            prefs.edit().putString("popup_sessions", PopupSessionStore.toJSONArray(sessions).toString()).apply()
        } catch (e: Exception) {
            Log.e("PetSvc", "updateSessionMeta failed: ${e.message}")
        }
    }

    /** 列出所有弹窗会话（供 Flutter 侧调用） */
    fun listPopupSessions(): List<Map<String, Any>> {
        try {
            ensureSessionIndex()
            val prefs = getSharedPreferences("pet_chat", android.content.Context.MODE_PRIVATE)
            val raw = prefs.getString("popup_sessions", null) ?: return emptyList()
            val arr = PopupSessionStore.parseSessionsArray(raw, this)
            val result = mutableListOf<Map<String, Any>>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                result.add(mapOf(
                    "id" to obj.getString("id"),
                    "title" to (obj.optString("title", "新对话")),
                    "createdAt" to obj.optLong("createdAt", 0L),
                    "msgCount" to obj.optInt("msgCount", 0)
                ))
            }
            return result
        } catch (e: Exception) { return emptyList() }
    }

    /** 创建新弹窗会话 */
    fun createPopupSession(): String {
        val id = System.currentTimeMillis().toString()
        val prefs = getSharedPreferences("pet_chat", android.content.Context.MODE_PRIVATE)
        prefs.edit().putString("last_session_id", id).apply()
        ensureSessionIndex()
        updateSessionMeta(id, "新对话", 0)
        Log.d("PetSvc", "popup session created: $id")
        return id
    }

    /** 删除弹窗会话 */
    fun deletePopupSession(sessionId: String) {
        try {
            val prefs = getSharedPreferences("pet_chat", android.content.Context.MODE_PRIVATE)
            val editor = prefs.edit()
            val msgCount = prefs.getInt("msg_count_$sessionId", 0)
            for (i in 0 until msgCount) {
                editor.remove("msg_${sessionId}_${i}_isUser")
                editor.remove("msg_${sessionId}_${i}_text")
            }
            editor.remove("msg_count_$sessionId")
            editor.apply()

            // 从索引移除
            val raw = prefs.getString("popup_sessions", null) ?: "[]"
            val arr = PopupSessionStore.parseSessionsArray(raw, this)
            val newArr = org.json.JSONArray()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                if (obj.getString("id") != sessionId) {
                    newArr.put(obj)
                }
            }
            prefs.edit().putString("popup_sessions", newArr.toString()).apply()

            // 如果删除的是当前会话 → 指向剩余最新的
            val lastId = prefs.getString("last_session_id", null)
            if (lastId == sessionId) {
                val sessions = listPopupSessions()
                if (sessions.isNotEmpty()) {
                    prefs.edit().putString("last_session_id", sessions.first()["id"] as String).apply()
                } else {
                    prefs.edit().remove("last_session_id").apply()
                }
            }

            Log.d("PetSvc", "popup session deleted: $sessionId ($msgCount msgs)")
        } catch (e: Exception) {
            Log.e("PetSvc", "deletePopupSession failed: ${e.message}")
        }
    }

    /** 切换弹窗会话（仅更新 last_session_id，不清空内存） */
    fun switchPopupSession(sessionId: String) {
        try {
            val prefs = getSharedPreferences("pet_chat", android.content.Context.MODE_PRIVATE)
            prefs.edit().putString("last_session_id", sessionId).apply()
            Log.d("PetSvc", "popup session switched → $sessionId")
        } catch (e: Exception) {
            Log.e("PetSvc", "switchPopupSession failed: ${e.message}")
        }
    }

    /** 获取弹窗会话消息（供 MethodChannel 调用） */
    fun getPopupSessionMessages(sessionId: String?): List<Map<String, Any>> {
        try {
            val prefs = getSharedPreferences("pet_chat", android.content.Context.MODE_PRIVATE)
            val sid = sessionId ?: prefs.getString("last_session_id", null) ?: return emptyList()
            val msgCount = prefs.getInt("msg_count_$sid", 0)
            val result = mutableListOf<Map<String, Any>>()
            for (i in 0 until msgCount) {
                val isUser = prefs.getBoolean("msg_${sid}_${i}_isUser", false)
                val text = prefs.getString("msg_${sid}_${i}_text", "") ?: ""
                if (text.isNotEmpty()) result.add(mapOf("isUser" to isUser, "text" to text))
            }
            return result
        } catch (e: Exception) { return emptyList() }
    }

    /** 保存单条消息到指定会话（供 Flutter 侧弹窗聊天持久化） */
    fun savePopupMessage(sessionId: String, isUser: Boolean, text: String) {
        try {
            val prefs = getSharedPreferences("pet_chat", android.content.Context.MODE_PRIVATE)
            val msgCount = prefs.getInt("msg_count_$sessionId", 0)
            prefs.edit()
                .putBoolean("msg_${sessionId}_${msgCount}_isUser", isUser)
                .putString("msg_${sessionId}_${msgCount}_text", text)
                .putInt("msg_count_$sessionId", msgCount + 1)
                .putString("last_session_id", sessionId)
                .apply()
            currentChatSessionId = sessionId
            ensureSessionIndex()
            val title = if (isUser)
                (if (text.length <= 20) text else text.substring(0, 20) + "...")
            else null
            updateSessionMeta(sessionId, title, msgCount + 1)
            Log.d("PetSvc", "savePopupMessage: sid=$sessionId isUser=$isUser len=${text.length}")
        } catch (e: Exception) {
            Log.e("PetSvc", "savePopupMessage failed: ${e.message}")
        }
    }

    /** 持久化当前聊天记录到 SharedPreferences */
    private fun saveChatHistory() {
        if (chatMessages.isEmpty()) return
        try {
            val sessionId = currentChatSessionId ?: System.currentTimeMillis().toString()
            currentChatSessionId = sessionId
            val prefs = getSharedPreferences("pet_chat", android.content.Context.MODE_PRIVATE)
            val editor = prefs.edit()
            editor.putString("last_session_id", sessionId)
            editor.putInt("msg_count_$sessionId", chatMessages.size)
            for (i in chatMessages.indices) {
                val m = chatMessages[i]
                editor.putBoolean("msg_${sessionId}_${i}_isUser", m.isUser)
                editor.putString("msg_${sessionId}_${i}_text", m.text)
            }
            editor.apply()

            // 提取会话标题（首条用户消息前 20 字）
            val firstUserMsg = chatMessages.firstOrNull { it.isUser && it.text.isNotEmpty() }
            val title = if (firstUserMsg != null)
                (if (firstUserMsg.text.length <= 20) firstUserMsg.text else firstUserMsg.text.substring(0, 20) + "...")
                else "新对话"
            // 更新多会话索引
            ensureSessionIndex()
            updateSessionMeta(sessionId, if (title == "新对话") null else title, chatMessages.size)

            Log.d("PetSvc", "saved ${chatMessages.size} history messages, session=$sessionId")
        } catch (e: Exception) {
            Log.e("PetSvc", "saveChatHistory failed: ${e.message}")
        }
    }

    /** 聊天弹窗引用（用于关闭） */
    private var chatDialogView: android.view.View? = null
    private var chatOverlayView: android.view.View? = null
    // 聊天消息状态
    private val chatMessages = mutableListOf<ChatMsg>()
    private var chatMsgContainer: android.widget.LinearLayout? = null
    private var chatScrollView: android.widget.ScrollView? = null
    private var chatInput: android.widget.EditText? = null
    private var chatLoadingView: android.view.View? = null
    private var chatWelcomeHint: android.widget.TextView? = null
    private var chatIdleTimer: java.util.Timer? = null
    private var chatRequestId = 0
    private var currentChatSessionId: String? = null  // 持久化会话 ID
    private var loadingAnimator: android.animation.ValueAnimator? = null
    private data class ChatMsg(val isUser: Boolean, val text: String, val isStreaming: Boolean = false)

    // ═══════════════════════════════════════════
    // 长按快捷菜单
    // ═══════════════════════════════════════════

    /** 长按 → 快捷菜单（喂食 / 玩耍 / 状态 / 日记） */
    private fun showQuickMenu(px: Float, py: Float) {
        val petView = this.petView ?: return
        val ctx = this@PetForegroundService
        val density = resources.displayMetrics.density
        val dp = { n: Int -> (n * density).toInt() }
        val colorBg = 0xFF212124.toInt()
        val colorBorder = 0xFF3A3A3E.toInt()
        val colorText = 0xFFE4DFD8.toInt()
        val colorAccent = 0xFFB8935D.toInt()

        val root = android.widget.FrameLayout(ctx).apply {
            setPadding(dp(4), dp(4), dp(4), dp(4))
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(colorBg)
                cornerRadius = dp(10).toFloat()
                setStroke(dp(1), colorBorder)
            }
            elevation = dp(8).toFloat()
        }

        val column = android.widget.LinearLayout(ctx).apply {
            orientation = android.widget.LinearLayout.VERTICAL
        }

        data class MenuItem(val icon: String, val label: String, val action: String)
        val items = listOf(
            MenuItem("🍖", "喂食", "feed"),
            MenuItem("🎾", "玩耍", "play"),
            MenuItem("📊", "状态", "status"),
            MenuItem("📝", "日记", "diary"),
        )

        for (item in items) {
            val btn = android.widget.TextView(ctx).apply {
                text = "${item.icon}  ${item.label}"
                setTextColor(colorText)
                textSize = 14f
                setPadding(dp(16), dp(12), dp(16), dp(12))
                setOnClickListener {
                    when (item.action) {
                        "feed" -> {
                            petView.playAnim("talking")
                            petView.showBubble("好吃~ 😋", 2000)
                            touchConsumer?.invoke("feed", px, py)
                        }
                        "play" -> {
                            petView.playAnim("jump")
                            petView.showBubble("来玩吧！🎾", 2000)
                            touchConsumer?.invoke("play", px, py)
                        }
                        "status" -> touchConsumer?.invoke("status", px, py)
                        "diary" -> touchConsumer?.invoke("diary", px, py)
                    }
                    dismissQuickMenu()
                }
            }
            column.addView(btn)
        }

        root.addView(column)

        val type = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O)
            android.view.WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION")
            android.view.WindowManager.LayoutParams.TYPE_PHONE

        val params = android.view.WindowManager.LayoutParams(
            android.view.WindowManager.LayoutParams.WRAP_CONTENT,
            android.view.WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            android.view.WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            android.view.WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            android.graphics.PixelFormat.TRANSLUCENT
        ).apply {
            gravity = android.view.Gravity.TOP or android.view.Gravity.START
            x = px.toInt() - dp(20)
            y = py.toInt() - dp(140)  // 菜单出现在手指上方
        }

        quickMenuView = root
        windowManager?.addView(root, params)

        // 3 秒自动消失
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            dismissQuickMenu()
        }, 4000)
    }

    private fun dismissQuickMenu() {
        try {
            quickMenuView?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {}
        quickMenuView = null
    }

    private var quickMenuView: android.view.View? = null

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
        dismissQuickMenu()   // 清理快捷菜单
        hidePetWindow()
        super.onDestroy()
    }
}
