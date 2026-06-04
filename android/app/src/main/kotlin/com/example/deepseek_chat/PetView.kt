package com.example.deepseek_chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.PorterDuff
import android.util.Log
import android.view.Choreographer
import android.view.MotionEvent
import android.view.View
import kotlin.math.abs

/**
 * 宠物渲染 Custom View — 整合物理/动画/气泡/触控。
 * Choreographer 驱动 60fps，LAYER_TYPE_HARDWARE GPU 加速。
 */
/** 透明模式状态 */
enum class TransparencyState { NORMAL, TRANSPARENT }

class PetView(context: Context) : View(context) {

    // 核心组件
    val physics = PetPhysics()
    val blender = FrameBlender()
    val bubble = BubbleAnimator()

    // 渲染循环
    private var lastFrameTime = 0L
    private var isRenderLoopRunning = false
    private var targetFps = 60

    // 触控
    private var downTime = 0L
    private var downX = 0f
    private var downY = 0f
    private var isDragging = false
    private var hasMoved = false
    private var lastClickTime = 0L
    private var pokeCount = 0
    private var pokeTimer = 0f

    // 透明模式
    var transparentState = TransparencyState.NORMAL
        private set
    /** 空闲超时分钟数（由 Dart 端同步），默认 5 分钟 */
    var transparentIdleMinutes = 5
    private var idleTime = 0f

    // 3连击检测（环形缓冲区）
    private val tapTimestamps = LongArray(3) { 0 }
    private var tapIndex = 0
    // 双击延迟执行 → 给第3次 tap 取消窗口
    private val tapHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var pendingDoubleTap: Runnable? = null

    // 视线跟随
    private var cursorX = 0f
    private var cursorY = 0f
    private var lookOffset = 0f  // 头部微偏角度

    // 动画修饰器（代码模拟动画，无需新帧）
    var currentAnimName = "idle"
    private var drawOffsetX = 0f
    private var drawOffsetY = 0f
    private var animScaleX = 1f
    private var animScaleY = 1f
    private var walkPhase = 0f
    private var talkPhase = 0f
    private var hungryPhase = 0f

    // 回调（Dart 端通过 MethodChannel 接收）
    var onTouchEvent: ((String, Float, Float) -> Unit)? = null
    var onArrive: ((Float, Float) -> Unit)? = null
    var onAnimEnd: ((String) -> Unit)? = null
    var onPokeCount: ((Int) -> Unit)? = null
    /** 宠物屏幕位置变化 → Service 重定位浮窗 */
    var onPositionChanged: ((Float, Float) -> Unit)? = null
    /** 用户触摸 → Service 禁用穿透 */
    var onUserInteraction: (() -> Unit)? = null

    // 宠物尺寸（由外部设置，默认 156dp = 120dp × 1.3）
    var petWidth = 156f
    var petHeight = 156f

    /** 仅视觉放大的倍率（触控命中区保持原 petWidth×petHeight 不变），默认 1.5x */
    var renderScale = 1.5f

    init {
        setLayerType(LAYER_TYPE_HARDWARE, null)
        setBackgroundColor(Color.TRANSPARENT)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        // 窗口宽 = 取视觉缩放宽度和触控宽度的较大值（确保缩放后不裁切）
        val displayW = (petWidth * renderScale).toInt().coerceAtLeast(petWidth.toInt())
        val displayH = (petHeight * renderScale).toInt()
        val bubbleReserve = (petHeight * 0.42f * renderScale).toInt()
        setMeasuredDimension(displayW, displayH + bubbleReserve)
    }

    // ═══════════════════════════════════════════
    // 公共接口
    // ═══════════════════════════════════════════

    fun startRenderLoop(fps: Int = 60) {
        if (isRenderLoopRunning) return
        isRenderLoopRunning = true
        targetFps = fps
        lastFrameTime = System.nanoTime()
        Log.d("PetView", "render loop start @${fps}fps, anims=${blender.listAnims()}, currentDef=${blender.currentBitmap()?.let{"${it.width}x${it.height}"} ?: "NULL"}")
        Choreographer.getInstance().postFrameCallback(renderLoop)
    }

    fun stopRenderLoop() {
        isRenderLoopRunning = false
        Log.d("PetView", "render loop stopped")
    }

    fun setFps(fps: Int) { targetFps = fps }

    /** 重置空闲计时（不退出透明模式） */
    fun resetIdleTimer() {
        idleTime = 0f
    }

    // 旧 passthrough 接口保留 stub，避免编译错误
    fun setPassthrough(enabled: Boolean) {
        // 已由透明模式替代，保留空实现兼容旧调用
    }

    // ═══════════════════════════════════════════
    // 随机漫步
    // ═══════════════════════════════════════════

    private var wanderHandler: android.os.Handler? = null
    private var wanderRunnable: Runnable? = null
    private var isWandering = false
    private var screenW = 1080
    private var screenH = 1920

    fun startWandering(sw: Int, sh: Int) {
        screenW = sw; screenH = sh
        wanderHandler = android.os.Handler(android.os.Looper.getMainLooper())
        scheduleWander()
        Log.d("PetView", "wandering started, screen=${sw}x${sh}")
    }

    fun stopWandering() {
        wanderHandler?.removeCallbacks(wanderRunnable ?: return)
        wanderHandler = null
        isWandering = false
    }

    private fun scheduleWander() {
        val h = wanderHandler ?: return
        val runnable = object : Runnable {
            override fun run() {
                // 仅当 idle 且不拖拽时发起漫步
                if (currentAnimName == "idle" && !physics.isMoving && !isDragging) {
                    val margin = petWidth * 2
                    val tx = (margin + Math.random() * (screenW - margin * 2)).toFloat()
                    val ty = (screenH * 0.1f + Math.random() * (screenH * 0.6f)).toFloat()
                    moveTo(tx, ty, 60f)
                    playAnim("run")
                    isWandering = true
                    Log.d("PetView", "wander → ($tx, $ty)")
                }
                h.postDelayed(this, 4000L + (Math.random() * 6000).toLong())
            }
        }
        wanderRunnable = runnable
        h.postDelayed(runnable, 5000L)
    }

    fun registerAnim(name: String, frames: List<android.graphics.Bitmap>, intervalMs: Long, loop: Boolean = true) {
        blender.register(name, FrameBlender.AnimDef(frames, intervalMs, loop))
    }

    fun playAnim(name: String) {
        // 仅当同名动画已在播放时跳过，避免重复 switchTo 导致帧跳回第0帧
        if (name == currentAnimName && blender.currentBitmap() != null) return
        Log.d("PetView", "playAnim('$name'): currentAnimName='$currentAnimName' currentBitmap=${blender.currentBitmap()}")
        currentAnimName = name
        blender.switchTo(name)
        Log.d("PetView", "playAnim('$name'): after switchTo, currentDef.frames.size=${blender.currentBitmap()?.let { "ok" } ?: "NULL"}")
        // 重置动画修饰器
        drawOffsetX = 0f; drawOffsetY = 0f
        animScaleX = 1f; animScaleY = 1f
        walkPhase = 0f; talkPhase = 0f; hungryPhase = 0f
    }

    fun showBubble(text: String, durationMs: Long = 3000) {
        bubble.show(text, durationMs)
    }

    fun moveTo(targetX: Float, targetY: Float, speed: Float = 200f) {
        physics.moveTo(targetX, targetY, speed)
        blender.facingLeft = targetX < physics.x
    }

    fun setEmotion(speed: Float = 1f, saturation: Float = 1f, grayscale: Float = 0f) {
        blender.setEmotion(speed, saturation, grayscale)
    }

    fun setFacing(left: Boolean) {
        blender.facingLeft = left
    }

    // ═══════════════════════════════════════════
    // 透明模式
    // ═══════════════════════════════════════════

    private fun isTripleTap(): Boolean {
        val now = System.currentTimeMillis()
        val allFilled = tapTimestamps.all { it > 0L }
        val oldest = tapTimestamps.min()
        return allFilled && (now - oldest) < 1500
    }

    fun toggleTransparent() {
        when (transparentState) {
            TransparencyState.NORMAL -> enterTransparent("manual")
            TransparencyState.TRANSPARENT -> exitTransparent("tripleTap")
        }
    }

    private fun enterTransparent(reason: String) {
        if (transparentState == TransparencyState.TRANSPARENT) return
        transparentState = TransparencyState.TRANSPARENT
        alpha = 0.3f
        idleTime = 0f
        Log.d("PetView", "transparency: ENTER (reason=$reason)")
    }

    private fun cancelPendingDoubleTap() {
        pendingDoubleTap?.let { tapHandler.removeCallbacks(it) }
        pendingDoubleTap = null
    }

    private fun exitTransparent(reason: String) {
        if (transparentState == TransparencyState.NORMAL) return
        transparentState = TransparencyState.NORMAL
        alpha = 1.0f
        idleTime = 0f
        Log.d("PetView", "transparency: EXIT (reason=$reason)")
    }

    fun listAnimNames(): Set<String> = blender.listAnims()

    // ═══════════════════════════════════════════
    // 渲染循环
    // ═══════════════════════════════════════════

    private val renderLoop = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!isRenderLoopRunning) return

            val dt = (frameTimeNanos - lastFrameTime) / 1_000_000_000f
            lastFrameTime = frameTimeNanos

            // 帧率控制
            val minDt = 1f / targetFps
            if (dt < minDt && targetFps < 60) {
                Choreographer.getInstance().postFrameCallback(this)
                return
            }

            update(dt.coerceAtMost(0.1f))  // 防止大帧跳跃
            invalidate()

            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    private var lastReportedX = -1f
    private var lastReportedY = -1f

    private fun update(dt: Float) {
        // 空闲计时：不拖拽、不漫步、物理静止时计时
        if (!isDragging && !isWandering && !physics.isMoving) {
            idleTime += dt
            // 自动进入透明模式
            if (transparentState == TransparencyState.NORMAL && idleTime > transparentIdleMinutes * 60f) {
                enterTransparent("idle")
            }
        } else {
            idleTime = 0f
        }

        // 连戳计时
        pokeTimer += dt
        if (pokeTimer > 2f) pokeCount = 0

        // 视线跟随：缓慢衰减
        lookOffset *= 0.95f

        // 物理
        physics.update(dt, isDragging, physics.x, physics.y)

        // 动画
        val animEnded = blender.update(dt)

        // 动画修饰器（代码模拟动画效果）
        updateAnimModifiers(dt)

        // 到达检测：漫步到达目的地 → 切回 idle，清零速度防残留下坠
        if (!physics.isMoving && !isDragging && isWandering) {
            isWandering = false
            physics.vx = 0f; physics.vy = 0f
            if (currentAnimName == "run") {
                playAnim("idle")
                Log.d("PetView", "wander arrived → idle, velocity zeroed")
            }
        }

        // 位置变化 → 通知 Service 重定位浮窗（小窗模式）
        if (abs(physics.x - lastReportedX) > 0.5f || abs(physics.y - lastReportedY) > 0.5f) {
            lastReportedX = physics.x; lastReportedY = physics.y
            onPositionChanged?.invoke(physics.x, physics.y)
        }

        // 气泡
        bubble.update(dt)
    }

    private fun updateAnimModifiers(dt: Float) {
        when (currentAnimName) {
            "walk" -> {
                // 走路：正弦摇摆 + 上下弹跳，8步/秒
                walkPhase += dt * 8f
                drawOffsetY = kotlin.math.sin(walkPhase * 2f) * 5f      // 上下弹跳 ±5px
                drawOffsetX = kotlin.math.cos(walkPhase) * 3f            // 左右摇摆 ±3px
                val step = kotlin.math.abs(kotlin.math.sin(walkPhase * 2f))
                animScaleY = 1f - step * 0.12f                            // 踩地时压缩
                animScaleX = 1f + step * 0.08f                            // 踩地时拉宽
            }
            "sit" -> {
                // 坐下：持续Y轴压缩 + 下沉，缓慢过渡
                val targetScale = 0.72f
                animScaleY += (targetScale - animScaleY) * 3f * dt       // 平滑过渡到 0.72x
                animScaleX += (1f / targetScale - animScaleX) * 3f * dt  // 保持体积，X 轴膨胀
                drawOffsetY += (12f - drawOffsetY) * 3f * dt              // 下沉 12px
                drawOffsetX *= kotlin.math.max(0f, 1f - 4f * dt)         // X 衰减
            }
            "sleeping" -> {
                // 睡觉：呼吸式缩放（极慢，5秒一个周期）
                val breathe = kotlin.math.sin(System.currentTimeMillis() / 5000.0).toFloat()
                animScaleX = 1f + breathe * 0.03f
                animScaleY = 1f + breathe * 0.04f
                drawOffsetX *= 0.9f
                drawOffsetY *= 0.9f
            }
            "talking" -> {
                // 说话：微小Y轴弹跳，6次/秒
                talkPhase += dt * 6f
                drawOffsetY = kotlin.math.sin(talkPhase * 2f) * 2f
                animScaleY = 1f + kotlin.math.abs(kotlin.math.sin(talkPhase * 2f)) * 0.04f
                drawOffsetX *= 0.9f
            }
            "hungry" -> {
                // 饿了：微颤 + 轻微摇摆
                hungryPhase += dt * 3f
                drawOffsetX = kotlin.math.sin(hungryPhase) * 2f
                drawOffsetY = kotlin.math.cos(hungryPhase * 1.3f) * 2f
                animScaleX = 1f + kotlin.math.sin(hungryPhase * 0.7f) * 0.02f
                animScaleY = 1f - kotlin.math.sin(hungryPhase * 0.7f) * 0.02f
            }
            "idle" -> {
                // 呼吸动画：~4秒周期，幅度 ±2%，模拟活物感
                val idlePhase = (System.currentTimeMillis() / 1000.0).toFloat()
                val breathe = kotlin.math.sin(idlePhase * 1.5f)  // ~4.2s 周期
                animScaleX = 1f + breathe * 0.025f
                animScaleY = 1f + breathe * 0.03f
                // 微小Y轴浮动，模拟站立时的身体微晃
                drawOffsetY = breathe * 1.5f
                drawOffsetX *= kotlin.math.max(0f, 1f - 3f * dt)
                // 踩地时squash恢复（从其他动画切换来时）
                if (kotlin.math.abs(animScaleX - 1f) < 0.01f) { animScaleX = 1f; animScaleY = 1f }
            }
            else -> {
                // 未知动画：缓慢归位
                drawOffsetX *= 0.9f
                drawOffsetY *= 0.9f
                animScaleX += (1f - animScaleX) * 2f * dt
                animScaleY += (1f - animScaleY) * 2f * dt
            }
        }
    }

    private var drawFrameCount = 0

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(0, PorterDuff.Mode.CLEAR)  // 透明

        // 视觉缩放后的精灵尺寸
        val visualW = petWidth * renderScale
        val visualH = petHeight * renderScale
        val bubbleReserve = measuredHeight - visualH.toInt()

        // 精灵水平居中，底部对齐
        val drawX = (measuredWidth - visualW) / 2f + drawOffsetX * renderScale
        val drawY = bubbleReserve + drawOffsetY * renderScale

        if (drawFrameCount < 5) {
            val bmp = blender.currentBitmap()
            Log.d("PetView", "onDraw #$drawFrameCount: drawXY=($drawX,$drawY) visualWH=${visualW.toInt()}x${visualH.toInt()} physicsXY=(${physics.x},${physics.y}) bmp=$bmp viewSize=$width×$height renderScale=$renderScale")
        }
        blender.draw(canvas, drawX, drawY,
            physics.squashX * animScaleX * renderScale,
            physics.squashY * animScaleY * renderScale)

        // 气泡（绘制在精灵上方，宽度匹配视觉尺寸）
        bubble.draw(canvas, drawX, drawY, visualW)
        drawFrameCount++
    }

    // ═══════════════════════════════════════════
    // 触控
    // ═══════════════════════════════════════════

    override fun onTouchEvent(event: MotionEvent): Boolean {
        // ── 命中测试：仅 ACTION_DOWN 检查是否点中精灵 ──
        // FrameBlender 以 bitmap 原生尺寸为中心缩放渲染，视觉中心在 bitmap 中心，不在 petWidth*renderScale
        if (event.action == MotionEvent.ACTION_DOWN) {
            val bmp = blender.currentBitmap()
            val bmpW = (bmp?.width ?: 192).toFloat()
            val bmpH = (bmp?.height ?: 208).toFloat()
            val displayW = (petWidth * renderScale).toInt().toFloat()
            val displayH = (petHeight * renderScale).toInt().toFloat()
            val topBarH = measuredHeight - displayH.toInt()
            val drawX = (measuredWidth - displayW) / 2f
            val drawY = topBarH.toFloat()
            // 视觉中心 = FrameBlender 的缩放锚点 (bitmap 中心)
            val visualCenterX = drawX + bmpW / 2f
            val visualCenterY = drawY + bmpH / 2f
            // 触控命中区 petWidth×petHeight，中心对齐视觉中心
            val spriteLeft = visualCenterX - petWidth / 2f
            val spriteTop = visualCenterY - petHeight / 2f
            val onSprite = event.x >= spriteLeft && event.x <= spriteLeft + petWidth &&
                           event.y >= spriteTop && event.y <= spriteTop + petHeight
            if (!onSprite) return false
        }

        idleTime = 0f  // 任何触控重置空闲计时
        onUserInteraction?.invoke()  // 通知 Service 禁用穿透

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                downTime = System.currentTimeMillis()
                downX = event.rawX
                downY = event.rawY
                hasMoved = false
                isDragging = false
            }
            MotionEvent.ACTION_MOVE -> {
                if (abs(event.rawX - downX) > 15f || abs(event.rawY - downY) > 15f) {
                    hasMoved = true
                    isDragging = true
                    // 拖拽 → 清空连击状态
                    tapTimestamps.fill(0); tapIndex = 0
                    // 手指对准视觉精灵中心（FrameBlender 以 bitmap 中心为锚点）
                    val bmp = blender.currentBitmap()
                    val bmpW = (bmp?.width ?: 192).toFloat()
                    val bmpH = (bmp?.height ?: 208).toFloat()
                    val displayW = (petWidth * renderScale).toInt().toFloat()
                    val topBarH = petHeight * 0.42f * renderScale
                    val drawX = (measuredWidth - displayW) / 2f
                    physics.x = event.rawX - drawX - bmpW / 2f
                    physics.y = event.rawY - topBarH - bmpH / 2f
                }
            }
            MotionEvent.ACTION_UP -> {
                val duration = System.currentTimeMillis() - downTime
                if (isDragging) {
                    // 拖拽松手 → 停在原地（桌面宠物不需要重力/惯性）
                    physics.vx = 0f; physics.vy = 0f
                    physics.enableGravity = false
                    cancelPendingDoubleTap()
                    onTouchEvent?.invoke("drag", event.rawX, event.rawY)
                } else if (!hasMoved) {
                    if (duration < 300) {
                        // 记录 tap 时间戳（用于 3连击检测）
                        tapTimestamps[tapIndex % 3] = System.currentTimeMillis()
                        tapIndex = (tapIndex + 1) % 3

                        // ── 3连击检测（优先级最高）──
                        if (isTripleTap()) {
                            cancelPendingDoubleTap()
                            toggleTransparent()
                            tapTimestamps.fill(0); tapIndex = 0
                            lastClickTime = 0
                            Log.d("PetView", "tripleTap → transparentState=$transparentState")
                        } else if ((System.currentTimeMillis() - lastClickTime) < 400) {
                            // 潜在双击 → 延迟执行，给第3次 tap 取消窗口（500ms）
                            lastClickTime = 0
                            cancelPendingDoubleTap()
                            val rawX = event.rawX; val rawY = event.rawY
                            pendingDoubleTap = Runnable {
                                onTouchEvent?.invoke("doubleTap", rawX, rawY)
                                pendingDoubleTap = null
                            }
                            tapHandler.postDelayed(pendingDoubleTap!!, 500)
                        } else {
                            // 单击
                            lastClickTime = System.currentTimeMillis()
                            if (transparentState == TransparencyState.NORMAL) {
                                // 正常模式：弹跳
                                pokeCount++
                                pokeTimer = 0f
                                onTouchEvent?.invoke("tap", event.rawX, event.rawY)
                                onPokeCount?.invoke(pokeCount)
                                physics.squashX = 1.15f
                                physics.squashY = 0.85f
                            }
                            // 透明模式：忽略单击（概念穿透）
                        }
                    } else if (duration >= 500) {
                        // 长按
                        cancelPendingDoubleTap()
                        tapTimestamps.fill(0); tapIndex = 0
                        if (transparentState == TransparencyState.NORMAL) {
                            onTouchEvent?.invoke("longPress", event.rawX, event.rawY)
                        }
                        // 透明模式：忽略长按
                    }
                }
                isDragging = false
                hasMoved = false
            }
            MotionEvent.ACTION_CANCEL -> {
                cancelPendingDoubleTap()
                isDragging = false
                hasMoved = false
            }
        }
        return true
    }

    override fun onHoverEvent(event: MotionEvent): Boolean {
        // 透明模式下不响应悬停（保持透明 alpha）
        if (transparentState == TransparencyState.TRANSPARENT) return false
        when (event.action) {
            MotionEvent.ACTION_HOVER_ENTER -> {
                alpha = 0.7f  // 轻微半透明提示可交互
            }
            MotionEvent.ACTION_HOVER_MOVE -> {
                cursorX = event.x
                cursorY = event.y
                val dx = event.x - petWidth / 2
                lookOffset = (dx / petWidth).coerceIn(-0.1f, 0.1f)
            }
            MotionEvent.ACTION_HOVER_EXIT -> {
                alpha = 1f
                lookOffset = 0f
            }
        }
        return true
    }
}
