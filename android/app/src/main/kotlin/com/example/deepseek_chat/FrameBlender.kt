package com.example.deepseek_chat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import kotlin.math.abs
import kotlin.random.Random

/**
 * 帧混合渲染器：帧序列播放 + 动画切换交叉淡入淡出 + 情绪变体 + 微动 overlay。
 */
class FrameBlender {

    /** 动画状态：帧数组 + 帧间隔(ms) */
    data class AnimDef(val frames: List<Bitmap>, val intervalMs: Long, val loop: Boolean = true)

    private val anims = mutableMapOf<String, AnimDef>()
    private var currentName = ""
    private var currentDef: AnimDef? = null
    private var currentIndex = 0
    private var elapsed = 0L
    private var directionForward = true

    // 交叉淡入淡出
    private var prevBitmap: Bitmap? = null
    private var blendAlpha = 0f        // 0=全旧, 1=全新
    private val blendDuration = 0.2f    // 200ms 过渡
    private val blendPaint = Paint()

    // 情绪变体
    var emotionSpeed = 1f       // 播放速度倍率（开心=1.2, 伤心=0.8）
    var emotionSaturation = 1f  // 饱和度倍率
    var emotionGrayscale = 0f   // 灰度比例（伤心=0.2）
    private val emotionPaint = Paint()

    // 微动 overlay
    private var blinkTimer = 0f
    private var blinkDuration = 0f
    private var isBlinking = false
    private var earWiggleTimer = 0f
    private var earWiggleOffset = 0f
    private val rng = Random(System.currentTimeMillis())

    // 朝向（false=朝右, true=朝左）
    var facingLeft = false

    /**
     * 注册一个动画。
     */
    fun register(name: String, def: AnimDef) {
        anims[name] = def
    }

    /**
     * 获取已注册的动画名称列表。
     */
    fun listAnims(): Set<String> = anims.keys

    /**
     * 切换到指定动画。如果已经在播放同名动画则忽略。
     */
    fun switchTo(name: String) {
        if (name == currentName) return
        val def = anims[name] ?: return
        prevBitmap = currentBitmap()
        blendAlpha = 0f
        currentName = name
        currentDef = def
        currentIndex = 0
        elapsed = 0L
        directionForward = true
    }

    /**
     * 每帧调用。dt 单位：秒。返回是否已到达动画末尾（非循环动画用）。
     */
    fun update(dt: Float): Boolean {
        val def = currentDef ?: return true

        // 过渡推进
        if (blendAlpha < 1f) {
            blendAlpha += dt / blendDuration
            if (blendAlpha >= 1f) {
                blendAlpha = 1f
                prevBitmap = null
            }
        }

        // 帧推进（考虑情绪速度）
        elapsed += (dt * 1000f * emotionSpeed).toLong()
        val frameInterval = def.intervalMs
        if (frameInterval > 0 && elapsed >= frameInterval) {
            val skip = (elapsed / frameInterval).toInt()
            elapsed %= frameInterval
            if (def.loop) {
                currentIndex = (currentIndex + skip) % def.frames.size
            } else {
                currentIndex = (currentIndex + skip).coerceAtMost(def.frames.size - 1)
                if (currentIndex >= def.frames.size - 1) return true  // 播完
            }
        }

        // 微动更新
        updateMicroExpressions(dt)

        return false
    }

    /**
     * 绘制当前帧到 canvas 的 (x, y) 位置。
     */
    fun draw(canvas: Canvas, x: Float, y: Float, scaleX: Float, scaleY: Float) {
        val bitmap = currentBitmap() ?: return

        canvas.save()

        // 方向翻转
        val cx = x + bitmap.width / 2f
        val cy = y + bitmap.height / 2f
        if (facingLeft) {
            canvas.scale(-1f, 1f, cx, cy)
        }

        // 弹性挤压
        canvas.scale(scaleX, scaleY, cx, cy)

        // 绘制前一帧（过渡中）
        if (blendAlpha < 1f && prevBitmap != null) {
            blendPaint.alpha = ((1f - blendAlpha) * 255).toInt()
            canvas.drawBitmap(prevBitmap!!, x, y, blendPaint)
        }

        // 绘制当前帧（过渡中带透明度）
        if (blendAlpha < 1f) {
            emotionPaint.alpha = (blendAlpha * 255).toInt()
        } else {
            emotionPaint.alpha = 255
        }

        // 情绪变体：构建颜色滤镜
        if (emotionGrayscale > 0f || emotionSaturation != 1f) {
            emotionPaint.colorFilter = buildEmotionFilter()
            canvas.drawBitmap(bitmap, x, y, emotionPaint)
            emotionPaint.colorFilter = null
        } else {
            canvas.drawBitmap(bitmap, x, y, emotionPaint)
        }

        // 微动 overlay
        drawMicroOverlays(canvas, x, y, bitmap.width.toFloat(), bitmap.height.toFloat())

        // 眨眼（遮盖眼部区域）
        if (isBlinking) {
            val eyeY = y + bitmap.height * 0.3f
            val eyeH = bitmap.height * 0.08f
            val eyePaint = Paint().apply { color = 0xFF000000.toInt(); alpha = 180 }
            // 仅当 idle 动画时绘制眨眼线
            if (currentName == "idle") {
                canvas.drawRect(x + bitmap.width * 0.25f, eyeY, x + bitmap.width * 0.45f, eyeY + eyeH, eyePaint)
                canvas.drawRect(x + bitmap.width * 0.55f, eyeY, x + bitmap.width * 0.75f, eyeY + eyeH, eyePaint)
            }
        }

        canvas.restore()
    }

    fun currentBitmap(): Bitmap? = currentDef?.frames?.getOrNull(currentIndex)

    private fun buildEmotionFilter(): PorterDuffColorFilter {
        val sat = (emotionSaturation * 255).toInt().coerceIn(0, 255)
        val gray = (emotionGrayscale * 255).toInt().coerceIn(0, 255)
        // 简化：用灰度混合
        val g = (gray * emotionGrayscale).toInt().coerceIn(0, 255)
        val color = android.graphics.Color.argb(255, sat, sat - g, sat - g)
        return PorterDuffColorFilter(color, PorterDuff.Mode.SRC_ATOP)
    }

    private fun updateMicroExpressions(dt: Float) {
        // 眨眼：概率 15%/5s
        blinkTimer += dt
        if (!isBlinking && blinkTimer > 3f && rng.nextFloat() < 0.03f) {
            isBlinking = true
            blinkDuration = 0.1f + rng.nextFloat() * 0.1f
            blinkTimer = 0f
        }
        if (isBlinking) {
            blinkDuration -= dt
            if (blinkDuration <= 0f) isBlinking = false
        }
        // 耳朵微动
        earWiggleTimer += dt
        if (earWiggleTimer > 2f && rng.nextFloat() < 0.05f) {
            earWiggleOffset = (rng.nextFloat() - 0.5f) * 3f
            earWiggleTimer = 0f
        }
        earWiggleOffset *= 0.9f  // 衰减
    }

    private fun drawMicroOverlays(canvas: Canvas, x: Float, y: Float, w: Float, h: Float) {
        // 耳朵微动 — 仅当 idle 动画时绘制微小偏移指示
        if (currentName == "idle" && abs(earWiggleOffset) > 0.5f) {
            // 在左耳位置画微小标记
            val earPaint = Paint().apply {
                alpha = (abs(earWiggleOffset) / 3f * 120).toInt()
                color = 0xFF000000.toInt()
            }
            canvas.drawCircle(
                x + w * 0.25f,
                y + h * 0.12f + earWiggleOffset,
                3f, earPaint
            )
            canvas.drawCircle(
                x + w * 0.75f,
                y + h * 0.12f - earWiggleOffset,
                3f, earPaint
            )
        }
    }

    /**
     * 设置情绪变体参数
     */
    fun setEmotion(speed: Float = 1f, saturation: Float = 1f, grayscale: Float = 0f) {
        emotionSpeed = speed
        emotionSaturation = saturation
        emotionGrayscale = grayscale
    }
}
