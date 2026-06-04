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

    // 点击穿透
    private var passthroughEnabled = false
    private var idleTime = 0f
    private val passthroughDelay = 8f  // 8 秒空闲后穿透

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
    /** 空闲超时 → Service 启用穿透 */
    var onIdleTimeout: (() -> Unit)? = null

    // 宠物尺寸（由外部设置，默认 156dp = 120dp × 1.3）
    var petWidth = 156f
    var petHeight = 156f

    init {
        setLayerType(LAYER_TYPE_HARDWARE, null)
        setBackgroundColor(Color.TRANSPARENT)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        // 窗口高度 = 精灵 + 气泡预留（约 40% 精灵高度用于气泡），精灵画在底部。
        // 触摸命中仅限底部精灵区域，气泡预留区设为透明且不响应触摸。
        val bubbleReserve = (petHeight * 0.42f).toInt()
        setMeasuredDimension(petWidth.toInt(), petHeight.toInt() + bubbleReserve)
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

    /** 重置空闲计时（Service 禁用穿透时调用） */
    fun resetIdleTimer() {
        idleTime = 0f
        idleTimeoutFired = false
    }

    fun setPassthrough(enabled: Boolean) {
        passthroughEnabled = enabled
        // 实际的 FLAG_NOT_TOUCHABLE 由 PetForegroundService 管理
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
    private var idleTimeoutFired = false

    private fun update(dt: Float) {
        // 空闲计时（穿透用）：不拖拽、不漫步、物理静止时计时
        if (!isDragging && !isWandering && !physics.isMoving) {
            idleTime += dt
            if (idleTime >= passthroughDelay && !idleTimeoutFired) {
                idleTimeoutFired = true
                onIdleTimeout?.invoke()
                Log.d("PetView", "idle timeout → request passthrough")
            }
        } else {
            idleTime = 0f
            idleTimeoutFired = false
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

        // 精灵帧：绘制在 View 底部（上方预留气泡空间，bubbleReserve = petHeight*0.42）
        val bubbleReserve = measuredHeight - petHeight.toInt()
        val drawX = 0f + drawOffsetX
        val drawY = bubbleReserve + drawOffsetY
        val bmp = blender.currentBitmap()
        if (drawFrameCount < 5) {
            Log.d("PetView", "onDraw #$drawFrameCount: drawXY=($drawX,$drawY) bubbleReserve=$bubbleReserve physicsXY=(${physics.x},${physics.y}) bmp=$bmp viewSize=$width×$height")
        }
        blender.draw(canvas, drawX, drawY,
            physics.squashX * animScaleX,
            physics.squashY * animScaleY)

        // 气泡（绘制在精灵上方，利用预留空间）
        bubble.draw(canvas, drawX, drawY, petWidth)
        drawFrameCount++
    }

    // ═══════════════════════════════════════════
    // 触控
    // ═══════════════════════════════════════════

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (passthroughEnabled) return false

        // ── 命中测试：仅 ACTION_DOWN 检查是否点中精灵 ──
        // 一旦手势开始（DOWN 通过），后续 MOVE/UP 不再检查，避免拖动时窗口跟随
        // 手指移动导致 event.x/y 相对位置变化而意外中断拖动。
        if (event.action == MotionEvent.ACTION_DOWN) {
            val spriteTop = (height - petHeight).coerceAtLeast(0f)
            val onSprite = event.x >= 0f && event.x <= petWidth &&
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
                    // 全屏自由拖动——桌面宠物可被拖到屏幕任意位置
                    physics.x = event.rawX - petWidth / 2
                    physics.y = event.rawY - petHeight / 2
                }
            }
            MotionEvent.ACTION_UP -> {
                val duration = System.currentTimeMillis() - downTime
                if (isDragging) {
                    // 拖拽松手 → 停在原地（桌面宠物不需要重力/惯性）
                    physics.vx = 0f; physics.vy = 0f
                    physics.enableGravity = false
                    onTouchEvent?.invoke("drag", event.rawX, event.rawY)
                } else if (!hasMoved) {
                    if (duration < 300) {
                        // 单击 or 双击
                        if (duration < 300 && (System.currentTimeMillis() - lastClickTime) < 400) {
                            // 双击
                            lastClickTime = 0
                            onTouchEvent?.invoke("doubleTap", event.rawX, event.rawY)
                        } else {
                            // 单击
                            lastClickTime = System.currentTimeMillis()
                            pokeCount++
                            pokeTimer = 0f
                            onTouchEvent?.invoke("tap", event.rawX, event.rawY)
                            onPokeCount?.invoke(pokeCount)
                            // 触控反馈：缩放弹跳
                            physics.squashX = 1.15f
                            physics.squashY = 0.85f
                        }
                    } else if (duration >= 500) {
                        // 长按
                        onTouchEvent?.invoke("longPress", event.rawX, event.rawY)
                    }
                }
                isDragging = false
                hasMoved = false
            }
            MotionEvent.ACTION_CANCEL -> {
                isDragging = false
                hasMoved = false
            }
        }
        return true
    }

    override fun onHoverEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_HOVER_ENTER -> {
                passthroughEnabled = false
                // 悬停 = 半透明
                alpha = 0.3f
            }
            MotionEvent.ACTION_HOVER_MOVE -> {
                cursorX = event.x
                cursorY = event.y
                // 视线跟随：头部微偏
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
