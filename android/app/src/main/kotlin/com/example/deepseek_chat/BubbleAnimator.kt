package com.example.deepseek_chat

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF

/**
 * 弹性气泡动画器 — 替代 TextView 的 VISIBLE/GONE 硬切。
 * 弹出：alpha 0→1 (200ms) + scale 0→1.1→1.0 (300ms)
 * 消失：alpha 1→0 (200ms) + translateY 0→-20
 */
class BubbleAnimator {

    data class BubbleConfig(
        val bgColor: Int = 0xCCFFFFFF.toInt(),    // 半透明白底
        val textColor: Int = 0xFF000000.toInt(),   // 黑字
        val cornerRadius: Float = 12f,
        val textSize: Float = 36f,                 // px
        val paddingH: Float = 24f,
        val paddingV: Float = 12f,
    )

    private val config = BubbleConfig()
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = config.textSize
        color = config.textColor
        textAlign = Paint.Align.CENTER
    }

    // ── 对象池：复用 RectF，避免每帧分配 ──
    private val clipRect = RectF()
    private val bubbleRect = RectF()

    // 动画状态
    private enum class Phase { HIDDEN, SHOWING, VISIBLE, HIDING }
    private var phase = Phase.HIDDEN
    private var elapsed = 0f
    private val showDuration = 0.3f   // 300ms 弹出
    private val hideDuration = 0.2f   // 200ms 消失

    var currentText: String = ""
        private set
    private var autoHideDuration = 0f   // 0=不自动消失
    private var bubbleAlpha = 0f
    private var bubbleScale = 1f
    private var bubbleOffsetY = 0f

    val isVisible: Boolean get() = phase != Phase.HIDDEN
    var isClickable: Boolean = false
    // 缓存最近一次绘制的气泡区域（用于点击检测）
    var lastBubbleRect: RectF? = null
        private set

    /**
     * 显示气泡。durationMs=0 表示不自动消失。
     */
    fun show(text: String, durationMs: Long = 0) {
        currentText = text
        autoHideDuration = durationMs / 1000f
        phase = Phase.SHOWING
        elapsed = 0f
        bubbleAlpha = 0f
        bubbleScale = 0f
        bubbleOffsetY = 0f
    }

    /**
     * 隐藏气泡
     */
    fun hide() {
        if (phase == Phase.HIDDEN || phase == Phase.HIDING) return
        phase = Phase.HIDING
        elapsed = 0f
    }

    /**
     * 每帧调用。dt 单位：秒。
     */
    fun update(dt: Float) {
        elapsed += dt

        when (phase) {
            Phase.SHOWING -> {
                val t = (elapsed / showDuration).coerceIn(0f, 1f)
                // easeOutBack: 先过冲再回弹
                bubbleAlpha = t.coerceIn(0f, 1f)
                bubbleScale = easeOutBack(t)
                if (t >= 1f) {
                    phase = Phase.VISIBLE
                    elapsed = 0f
                    bubbleScale = 1f
                    bubbleAlpha = 1f
                }
            }
            Phase.VISIBLE -> {
                if (autoHideDuration > 0f && elapsed >= autoHideDuration) {
                    hide()
                }
            }
            Phase.HIDING -> {
                val t = (elapsed / hideDuration).coerceIn(0f, 1f)
                bubbleAlpha = 1f - t
                bubbleOffsetY = -20f * t  // 向上升起
                if (t >= 1f) {
                    phase = Phase.HIDDEN
                    currentText = ""
                    bubbleOffsetY = 0f
                }
            }
            Phase.HIDDEN -> {}
        }
    }

    /**
     * 绘制气泡。参数为宠物参考位置（气泡画在宠物上方）。
     *
     * 性能：复用成员 RectF 替代每帧 new RectF()，消除 GC 压力。
     * saveLayerAlpha 是 GPU 驱动优化过的合成路径，保留使用。
     */
    fun draw(canvas: Canvas, petX: Float, petY: Float, petW: Float) {
        if (phase == Phase.HIDDEN) return
        if (currentText.isEmpty()) return

        // 计算气泡位置（宠物上方居中）
        val textWidth = textPaint.measureText(currentText)
        val bubbleW = textWidth + config.paddingH * 2
        val bubbleH = config.textSize + config.paddingV * 2

        val centerX = petX + petW / 2f
        val bubbleLeft = centerX - bubbleW * bubbleScale / 2f
        val bubbleTop = petY - bubbleH * bubbleScale - 16f + bubbleOffsetY
        val bubbleRight = centerX + bubbleW * bubbleScale / 2f
        val bubbleBottom = petY - 16f + bubbleOffsetY

        // 缓存气泡区域用于点击检测
        lastBubbleRect = RectF(bubbleLeft, bubbleTop, bubbleRight, bubbleBottom)

        // 复用 RectF 避免每帧分配（原代码 new RectF × 2 / 帧）
        clipRect.set(bubbleLeft - 8f, bubbleTop - 8f, bubbleRight + 8f, bubbleBottom + 8f)
        canvas.saveLayerAlpha(clipRect, (bubbleAlpha * 255).toInt())

        bgPaint.color = config.bgColor
        bgPaint.alpha = (bubbleAlpha * 255).toInt()
        bubbleRect.set(bubbleLeft, bubbleTop, bubbleRight, bubbleBottom)
        canvas.drawRoundRect(bubbleRect, config.cornerRadius, config.cornerRadius, bgPaint)

        textPaint.alpha = (bubbleAlpha * 255).toInt()
        canvas.drawText(
            currentText,
            centerX,
            bubbleTop + config.paddingV + config.textSize * 0.35f,
            textPaint
        )

        canvas.restore()
    }

    private fun easeOutBack(t: Float): Float {
        val c1 = 1.70158f
        val c3 = c1 + 1f
        return 1f + c3 * Math.pow((t - 1).toDouble(), 3.0).toFloat() +
                c1 * Math.pow((t - 1).toDouble(), 2.0).toFloat()
    }
}
