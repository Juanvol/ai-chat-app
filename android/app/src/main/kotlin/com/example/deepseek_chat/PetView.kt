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
    private val passthroughDelay = 3f  // 3 秒空闲后穿透

    // 视线跟随
    private var cursorX = 0f
    private var cursorY = 0f
    private var lookOffset = 0f  // 头部微偏角度

    // 回调（Dart 端通过 MethodChannel 接收）
    var onTouchEvent: ((String, Float, Float) -> Unit)? = null
    var onArrive: ((Float, Float) -> Unit)? = null
    var onAnimEnd: ((String) -> Unit)? = null
    var onPokeCount: ((Int) -> Unit)? = null

    // 宠物尺寸（由外部设置）
    var petWidth = 120f
    var petHeight = 120f

    init {
        setLayerType(LAYER_TYPE_HARDWARE, null)
        setBackgroundColor(Color.TRANSPARENT)
    }

    // ═══════════════════════════════════════════
    // 公共接口
    // ═══════════════════════════════════════════

    fun startRenderLoop(fps: Int = 60) {
        if (isRenderLoopRunning) return
        isRenderLoopRunning = true
        targetFps = fps
        lastFrameTime = System.nanoTime()
        Log.d("PetView", "render loop start @${fps}fps")
        Choreographer.getInstance().postFrameCallback(renderLoop)
    }

    fun stopRenderLoop() {
        isRenderLoopRunning = false
        Log.d("PetView", "render loop stopped")
    }

    fun setFps(fps: Int) { targetFps = fps }

    fun setPassthrough(enabled: Boolean) {
        passthroughEnabled = enabled
        // 实际的 FLAG_NOT_TOUCHABLE 由 PetForegroundService 管理
    }

    fun registerAnim(name: String, frames: List<android.graphics.Bitmap>, intervalMs: Long, loop: Boolean = true) {
        blender.register(name, FrameBlender.AnimDef(frames, intervalMs, loop))
    }

    fun playAnim(name: String) {
        blender.switchTo(name)
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

    private fun update(dt: Float) {
        // 空闲计时（穿透用）
        if (!isDragging) {
            idleTime += dt
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

        // 到达检测
        if (!physics.isMoving && !isDragging) {
            // 速度归零 → 到达
            // onArrive 由 Dart 端在收到速度归零后调用
        }

        // 气泡
        bubble.update(dt)
    }

    // ═══════════════════════════════════════════
    // 绘制
    // ═══════════════════════════════════════════

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(0, PorterDuff.Mode.CLEAR)  // 透明

        // 落地粒子
        for (p in physics.particles) {
            val paint = android.graphics.Paint().apply {
                color = Color.argb((p.alpha * 255).toInt(), 180, 180, 180)
                style = android.graphics.Paint.Style.FILL
            }
            canvas.drawCircle(p.x, p.y, 3f, paint)
        }

        // 精灵帧
        blender.draw(canvas, physics.x, physics.y, physics.squashX, physics.squashY)

        // 气泡
        bubble.draw(canvas, physics.x, physics.y, petWidth)
    }

    // ═══════════════════════════════════════════
    // 触控
    // ═══════════════════════════════════════════

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (passthroughEnabled) return false

        idleTime = 0f  // 任何触控重置空闲计时

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
                    physics.x = event.rawX - petWidth / 2
                    physics.y = event.rawY - petHeight / 2
                }
            }
            MotionEvent.ACTION_UP -> {
                val duration = System.currentTimeMillis() - downTime
                if (isDragging) {
                    // 拖拽松手 → 惯性飞行
                    physics.applyFling()
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
                            // 触控反馈：缩放弹跳（在下一帧的physics中体现）
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
