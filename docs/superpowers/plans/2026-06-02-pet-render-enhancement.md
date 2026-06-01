# 弗糯糯宠物渲染增强 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将弗糯糯宠物悬浮窗从"ImageView + Handler 15fps 贴图"升级为"Custom View + 硬件层 60fps 活物"，新增轻量物理引擎、行为决策系统、弹性气泡。

**Architecture:** 6 个新文件 + 3 个修改文件。Kotlin 端负责渲染/物理/动画（PetView + PetPhysics + FrameBlender + BubbleAnimator），Dart 端负责行为决策/气泡管理（PetBrain + PetBubbleManager）。通过现有 `pet_overlay` MethodChannel 扩展命令协议。

**Tech Stack:** Android Kotlin (Custom View + Choreographer + Canvas) + Flutter 3.24 / Dart 3.5 (ChangeNotifier + Hive)

---

## 文件结构

```
android/app/src/main/kotlin/com/example/deepseek_chat/
├── PetView.kt              🆕 Custom View + 硬件层渲染
├── PetPhysics.kt           🆕 轻量物理引擎
├── FrameBlender.kt         🆕 帧插值混合 + 情绪变体
├── BubbleAnimator.kt       🆕 弹性气泡动画
├── PetForegroundService.kt 🔧 重构（PetView 替代 ImageView）
lib/services/
├── pet_brain.dart          🆕 行为决策系统
├── pet_bubble_manager.dart 🆕 100+ 预设气泡
├── pet_overlay_host.dart   🔧 接入 PetBrain
lib/
└── main.dart               🔧 BubbleManager 注册
```

---

### Task 1: PetPhysics.kt — 轻量物理引擎

**Files:**
- Create: `android/app/src/main/kotlin/com/example/deepseek_chat/PetPhysics.kt`

**Purpose:** 纯数据类，无 Android 依赖。提供 6 个物理公式（重力、碰撞、弹性、惯性、摩擦、壁面滑落）+ 落地粒子 + 边缘粘停。

- [ ] **Step 1: 创建 PetPhysics.kt**

```kotlin
package com.example.deepseek_chat

import kotlin.math.abs
import kotlin.math.sqrt

/**
 * 轻量物理引擎 — 让宠物有重力/碰撞/弹性/惯性/摩擦/壁面滑落。
 * 纯数据类，不依赖 Android SDK，可独立单元测试。
 */
class PetPhysics(
    var x: Float = 100f,
    var y: Float = 400f,
    var vx: Float = 0f,
    var vy: Float = 0f,
    var squashX: Float = 1f,
    var squashY: Float = 1f,
) {
    // 物理常量
    private val gravity = 980f          // px/s²
    private val bounceCoefficient = 0.6f
    private val friction = 0.95f
    private val maxSquash = 0.7f
    private val squashRecovery = 0.08f

    // 屏幕边界（由外部设置）
    var minX = 0f
    var minY = 0f
    var maxX = 1080f
    var maxY = 1920f

    // 边缘粘停
    var isStuck = false
    private var stuckTimer = 0f
    private val stuckDuration = 0.5f  // 粘住 0.5 秒

    // 落地粒子（由外部读取并渲染后清除）
    data class LandingParticle(
        var x: Float, var y: Float,
        var vx: Float, var vy: Float,
        var alpha: Float = 1f
    )
    val particles = mutableListOf<LandingParticle>()

    // 位置历史（拖拽惯性用）
    private val positionHistory = Array(10) { Pair(0f, 0f) }
    private var historyIndex = 0

    val isMoving: Boolean get() = abs(vx) > 5f || abs(vy) > 5f

    /**
     * 每帧调用一次。dt 单位：秒。
     */
    fun update(dt: Float, isDragging: Boolean = false, dragX: Float = 0f, dragY: Float = 0f) {
        if (isDragging) {
            // 拖拽中：记录位置历史，清除速度
            positionHistory[historyIndex % 10] = Pair(dragX, dragY)
            historyIndex++
            x = dragX
            y = dragY
            vx = 0f; vy = 0f
            squashX = 1.08f; squashY = 0.92f  // 被抓时微挤压
            particles.clear()
            return
        }

        // 边缘粘停计时
        if (isStuck) {
            stuckTimer += dt
            squashX = 1.15f; squashY = 0.85f  // 挤压变形
            if (stuckTimer >= stuckDuration) {
                isStuck = false
                stuckTimer = 0f
                vx *= -bounceCoefficient  // 弹回
            }
            updateParticles(dt)
            recoverSquash()
            return
        }

        // 应用重力
        vy += gravity * dt

        // 应用速度
        x += vx * dt
        y += vy * dt

        // 边界碰撞
        if (x < minX) { x = minX; vx *= -bounceCoefficient; isStuck = true }
        if (x > maxX) { x = maxX; vx *= -bounceCoefficient; isStuck = true }
        if (y < minY) { y = minY; vy *= -bounceCoefficient; isStuck = true }
        if (y > maxY) {
            val wasFalling = vy > 300f
            y = maxY
            vy *= -bounceCoefficient
            // 落地挤压 + 粒子
            if (wasFalling) {
                squashX = maxSquash; squashY = 1f + (1f - maxSquash)
                spawnLandingParticles()
            }
            // 微小弹跳后如果速度很小就停住
            if (abs(vy) < 50f) vy = 0f
        }

        // 壁面滑落：碰竖边时保持 vy
        // （已通过上面的 x 边界碰撞实现）

        // 摩擦力
        vx *= friction
        if (!isStuck && y >= maxY - 1f) vy *= friction

        // 挤压恢复
        recoverSquash()

        // 粒子更新
        updateParticles(dt)
    }

    /**
     * 松手时根据位置历史计算惯性速度
     */
    fun applyFling() {
        if (historyIndex < 2) { vx = 0f; vy = 0f; return }
        val (px1, py1) = positionHistory[(historyIndex - 2) % 10]
        val (px2, py2) = positionHistory[(historyIndex - 1) % 10]
        vx = (px2 - px1) * 3f  // 系数放大
        vy = (py2 - py1) * 3f
        historyIndex = 0
    }

    /**
     * 命令移动到目标位置
     */
    fun moveTo(targetX: Float, targetY: Float, speed: Float = 200f) {
        val dx = targetX - x
        val dy = targetY - y
        val dist = sqrt(dx * dx + dy * dy)
        if (dist < 1f) return
        vx = (dx / dist) * speed
        vy = (dy / dist) * speed
    }

    private fun spawnLandingParticles() {
        particles.clear()
        for (i in 0 until 5) {
            particles.add(LandingParticle(
                x = x + (Math.random().toFloat() - 0.5f) * 80f,
                y = maxY,
                vx = (Math.random().toFloat() - 0.5f) * 200f,
                vy = -(Math.random().toFloat() * 300f + 100f)
            ))
        }
    }

    private fun updateParticles(dt: Float) {
        val iter = particles.iterator()
        while (iter.hasNext()) {
            val p = iter.next()
            p.x += p.vx * dt
            p.y += p.vy * dt
            p.vy += gravity * 0.5f * dt
            p.alpha -= 2f * dt
            if (p.alpha <= 0f) iter.remove()
        }
    }

    private fun recoverSquash() {
        squashX += (1f - squashX) * squashRecovery
        squashY += (1f - squashY) * squashRecovery
        if (abs(squashX - 1f) < 0.01f) { squashX = 1f; squashY = 1f }
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
cd android && ./gradlew :app:compileDebugKotlin
```

预期：编译通过（PetPhysics 无 Android 依赖，编译零风险）

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/example/deepseek_chat/PetPhysics.kt
git commit -m "feat: 新增 PetPhysics 轻量物理引擎

6 公式（重力/碰撞/弹性/惯性/摩擦/壁面）+ 落地粒子 + 边缘粘停。
纯数据类，无 Android 依赖，可独立单元测试。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: FrameBlender.kt — 帧插值混合器

**Files:**
- Create: `android/app/src/main/kotlin/com/example/deepseek_chat/FrameBlender.kt`

**Purpose:** 管理帧序列播放。提供动画切换时的交叉淡入淡出、情绪变体参数、微动 overlay（眨眼/耳朵）。

- [ ] **Step 1: 创建 FrameBlender.kt**

```kotlin
package com.example.deepseek_chat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import kotlin.math.abs
import kotlin.math.sin
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
```

- [ ] **Step 2: 验证编译**

```bash
cd android && ./gradlew :app:compileDebugKotlin
```

预期：编译通过

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/example/deepseek_chat/FrameBlender.kt
git commit -m "feat: 新增 FrameBlender 帧插值混合器

动画切换交叉淡入淡出(200ms) + 情绪变体(速度/饱和度/灰度)
+ 微动overlay(眨眼15%/5s + 耳朵微动10%/3s) + 方向翻转。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: BubbleAnimator.kt — 弹性气泡动画

**Files:**
- Create: `android/app/src/main/kotlin/com/example/deepseek_chat/BubbleAnimator.kt`

**Purpose:** 替换 TextView 硬切显隐。提供弹性弹出动画（Alpha + Scale + Translate）。

- [ ] **Step 1: 创建 BubbleAnimator.kt**

```kotlin
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

    // 动画状态
    private enum class Phase { HIDDEN, SHOWING, VISIBLE, HIDING }
    private var phase = Phase.HIDDEN
    private var elapsed = 0f
    private val showDuration = 0.3f   // 300ms 弹出
    private val hideDuration = 0.2f   // 200ms 消失

    private var currentText = ""
    private var autoHideDuration = 0f   // 0=不自动消失
    private var bubbleAlpha = 0f
    private var bubbleScale = 1f
    private var bubbleOffsetY = 0f

    val isVisible: Boolean get() = phase != Phase.HIDDEN

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
     */
    fun draw(canvas: Canvas, petX: Float, petY: Float, petW: Float) {
        if (phase == Phase.HIDDEN) return
        if (currentText.isEmpty()) return

        canvas.save()

        // 计算气泡位置（宠物上方居中）
        val textWidth = textPaint.measureText(currentText)
        val bubbleW = textWidth + config.paddingH * 2
        val bubbleH = config.textSize + config.paddingV * 2

        val centerX = petX + petW / 2f
        val bubbleLeft = centerX - bubbleW * bubbleScale / 2f
        val bubbleTop = petY - bubbleH * bubbleScale - 16f + bubbleOffsetY
        val bubbleRight = centerX + bubbleW * bubbleScale / 2f
        val bubbleBottom = petY - 16f + bubbleOffsetY

        // 缩放 + 透明度
        canvas.saveLayerAlpha(
            RectF(bubbleLeft - 8f, bubbleTop - 8f, bubbleRight + 8f, bubbleBottom + 8f),
            (bubbleAlpha * 255).toInt()
        )

        bgPaint.color = config.bgColor
        bgPaint.alpha = (bubbleAlpha * 255).toInt()
        canvas.drawRoundRect(
            RectF(bubbleLeft, bubbleTop, bubbleRight, bubbleBottom),
            config.cornerRadius, config.cornerRadius, bgPaint
        )

        textPaint.alpha = (bubbleAlpha * 255).toInt()
        canvas.drawText(
            currentText,
            centerX,
            bubbleTop + config.paddingV + config.textSize * 0.35f,
            textPaint
        )

        canvas.restore()
        canvas.restore()
    }

    private fun easeOutBack(t: Float): Float {
        val c1 = 1.70158f
        val c3 = c1 + 1f
        return 1f + c3 * Math.pow((t - 1).toDouble(), 3.0).toFloat() +
                c1 * Math.pow((t - 1).toDouble(), 2.0).toFloat()
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
cd android && ./gradlew :app:compileDebugKotlin
```

预期：编译通过

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/example/deepseek_chat/BubbleAnimator.kt
git commit -m "feat: 新增 BubbleAnimator 弹性气泡动画

替换 TextView VISIBLE/GONE 硬切：弹性弹出(easeOutBack 300ms)
+ 淡出升起(200ms)。纯 Canvas 绘制，无 View 层级开销。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: PetView.kt — Custom View 渲染核心

**Files:**
- Create: `android/app/src/main/kotlin/com/example/deepseek_chat/PetView.kt`

**Purpose:** 整合 PetPhysics + FrameBlender + BubbleAnimator 为单一 Custom View。Choreographer 驱动 60fps 渲染循环。

- [ ] **Step 1: 创建 PetView.kt**

```kotlin
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
```

- [ ] **Step 2: 验证编译**

```bash
cd android && ./gradlew :app:compileDebugKotlin
```

预期：编译通过

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/example/deepseek_chat/PetView.kt
git commit -m "feat: 新增 PetView Custom View 渲染核心

整合 PetPhysics + FrameBlender + BubbleAnimator。
Choreographer 60fps + LAYER_TYPE_HARDWARE GPU加速。
5 种手势识别（单击/双击/长按/拖拽/悬停）+ 连戳计数。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: 重构 PetForegroundService.kt

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/deepseek_chat/PetForegroundService.kt`

**Purpose:** 用 PetView 替代现有的 ImageView + Handler 动画系统。简化 Service 代码（从 ~360 行降至 ~200 行）。

**核心改动:**
1. `petImage: ImageView` → `petView: PetView`
2. `bubbleText: TextView` → 删除（由 PetView.bubble 接管）
3. `emojiText: TextView` → 删除（由 PetView 接管 emoji 绘制逻辑）
4. `loadedAnims` + `curAnim` + `animHandler` + `animRunnable` → 删除（由 FrameBlender 接管）
5. `handleCommand()` 扩展 `moveTo` / `setPassthrough` / `setFacing`

- [ ] **Step 1: 重写 PetForegroundService.kt**

```kotlin
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

            // 加载帧动画
            loadAllFrames()
            if (listAnimNames().isNotEmpty()) playAnim("idle")

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

            // 启动渲染循环
            startRenderLoop()
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
```

- [ ] **Step 2: 验证编译**

```bash
cd android && ./gradlew :app:compileDebugKotlin
```

预期：编译通过。如果 PetView 的 `listAnimNames()` 方法未定义，在 PetView.kt 添加：

```kotlin
fun listAnimNames(): Set<String> = blender.listAnims()
```

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/example/deepseek_chat/PetForegroundService.kt
git commit -m "refactor: PetForegroundService v2 — PetView 替代 ImageView

移除 ImageView/TextView/Handler 旧渲染管线。
PetView 统一接管渲染/动画/气泡/触控。
Service 行数 360→~200，逻辑更清晰。
新增 moveTo/setPassthrough/setFacing/setFps 命令。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: pet_brain.dart — 行为决策系统

**Files:**
- Create: `lib/services/pet_brain.dart`
- Create: `test/services/pet_brain_test.dart`

**Purpose:** 替代 PetOverlayController 中硬编码的 Timer 空闲行为。提供行为权重表、时段主题、空闲分层、戳宠进化。

- [ ] **Step 1: 创建测试文件**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/services/pet_brain.dart';
import 'package:ai_chat/services/pet_agent_core.dart';

void main() {
  group('BehaviorWeights', () {
    test('基础权重总和为 100', () {
      final w = BehaviorWeights();
      expect(w.total, 100);
    });

    test('深夜调整：睡眠权重×3，走动权重×0.3', () {
      final w = BehaviorWeights();
      w.applyContext(hour: 2, hunger: 80, energy: 80, mood: 0.5, al: AttentionLevel.L3);
      expect(w.sleep, greaterThan(30)); // 原本 ~10，×3 = 30
      expect(w.wander, lessThan(10));   // 原本 15，×0.3 = 4.5
    });

    test('饥饿时 hungryBubble 权重提升', () {
      final w = BehaviorWeights();
      final before = w.hungryBubble;
      w.applyContext(hour: 14, hunger: 20, energy: 80, mood: 0.5, al: AttentionLevel.L3);
      expect(w.hungryBubble, greaterThan(before));
    });

    test('疲劳时 sit 权重×2.5', () {
      final w = BehaviorWeights();
      w.applyContext(hour: 14, hunger: 80, energy: 10, mood: 0.5, al: AttentionLevel.L3);
      expect(w.sitDown, greaterThan(20)); // 原本 10，×2.5 = 25
    });

    test('L0 休眠全部归零除了睡眠', () {
      final w = BehaviorWeights();
      w.applyContext(hour: 14, hunger: 80, energy: 80, mood: 0.5, al: AttentionLevel.L0);
      expect(w.idleBreath, 0);
      expect(w.wander, 0);
      expect(w.sleep, greaterThan(0));
    });
  });

  group('IdleTier', () {
    test('0-20s 为 Tier1', () {
      expect(IdleTier.fromIdleSeconds(0), IdleTier.tier1);
      expect(IdleTier.fromIdleSeconds(19), IdleTier.tier1);
    });

    test('20-90s 为 Tier2', () {
      expect(IdleTier.fromIdleSeconds(20), IdleTier.tier2);
      expect(IdleTier.fromIdleSeconds(89), IdleTier.tier2);
    });

    test('90s+ 为 Tier3', () {
      expect(IdleTier.fromIdleSeconds(90), IdleTier.tier3);
      expect(IdleTier.fromIdleSeconds(999), IdleTier.tier3);
    });
  });

  group('DayPeriod', () {
    test('6-9 为早晨', () {
      expect(DayPeriod.fromHour(6), DayPeriod.morning);
      expect(DayPeriod.fromHour(8), DayPeriod.morning);
    });
    test('9-12 为上午', () => expect(DayPeriod.fromHour(10), DayPeriod.morningWork));
    test('12-18 为下午', () => expect(DayPeriod.fromHour(15), DayPeriod.afternoon));
    test('18-22 为傍晚', () => expect(DayPeriod.fromHour(20), DayPeriod.evening));
    test('22-6 为深夜', () {
      expect(DayPeriod.fromHour(23), DayPeriod.night);
      expect(DayPeriod.fromHour(3), DayPeriod.night);
    });
  });

  group('PokeTracker', () {
    test('1次戳不触发特殊反应', () {
      final t = PokeTracker();
      final r = t.recordPoke();
      expect(r, PokeReaction.none);
    });

    test('3次戳(2s内)触发 annoyed', () {
      final t = PokeTracker();
      t.recordPoke(); // 1
      t.recordPoke(); // 2
      final r = t.recordPoke(); // 3
      expect(r, PokeReaction.annoyed);
    });

    test('冷却后戳计数重置', () {
      final t = PokeTracker();
      t.recordPoke();
      t.recordPoke();
      t.recordPoke(); // annoyed
      // 模拟冷却
      t._pokeTimer = 999; // 冷却结束
      final r = t.recordPoke();
      expect(r, PokeReaction.none);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/services/pet_brain_test.dart
```

预期：全部 FAIL（文件尚未创建）

- [ ] **Step 3: 创建 pet_brain.dart**

```dart
// Flutter 3.24 / Dart 3.5
import 'dart:math';
import 'pet_agent_core.dart';

enum DayPeriod { morning, morningWork, afternoon, evening, night }

enum IdleTier { tier1, tier2, tier3 }

enum PokeReaction { none, bounce, annoyed, playDead }

extension DayPeriodExt on DayPeriod {
  static DayPeriod fromHour(int hour) => switch (hour) {
    >= 6 && < 9 => DayPeriod.morning,
    >= 9 && < 12 => DayPeriod.morningWork,
    >= 12 && < 18 => DayPeriod.afternoon,
    >= 18 && < 22 => DayPeriod.evening,
    _ => DayPeriod.night,
  };
}

extension IdleTierExt on IdleTier {
  static IdleTier fromIdleSeconds(int seconds) => switch (seconds) {
    < 20 => IdleTier.tier1,
    < 90 => IdleTier.tier2,
    _ => IdleTier.tier3,
  };
}

class BehaviorWeights {
  int idleBreath = 50;
  int lookAround = 20;
  int wander = 15;
  int sitDown = 10;
  int rareAction = 5;
  int hungryBubble = 8;
  int sleep = 2;
  int speakBubble = 5;

  int get total => idleBreath + lookAround + wander + sitDown +
      rareAction + hungryBubble + sleep + speakBubble;

  final _rng = Random();

  void applyContext({
    required int hour,
    required int hunger,
    required int energy,
    required double mood,
    required AttentionLevel al,
  }) {
    // 重置
    idleBreath = 50; lookAround = 20; wander = 15; sitDown = 10;
    rareAction = 5; hungryBubble = 8; sleep = 2; speakBubble = 5;

    // 时段主题
    switch (DayPeriodExt.fromHour(hour)) {
      case DayPeriod.morning:
        lookAround = (lookAround * 2).round();
        rareAction = (rareAction * 2).round();
      case DayPeriod.morningWork:
        idleBreath = (idleBreath * 1.5).round();
        wander = (wander * 0.5).round();
      case DayPeriod.afternoon:
        wander = (wander * 1.5).round();
        rareAction = (rareAction * 1.5).round();
      case DayPeriod.evening:
        speakBubble = (speakBubble * 2).round();
        sitDown = (sitDown * 2).round();
      case DayPeriod.night:
        sleep = (sleep * 3).round();
        wander = (wander * 0.3).round();
        speakBubble = (speakBubble * 0.3).round();
    }

    // 身体状态
    if (hunger < 30) hungryBubble = (hungryBubble * 4).round();
    if (energy < 20) { sitDown = (sitDown * 2.5).round(); wander = (wander * 0.2).round(); }
    if (mood > 0.8) rareAction = (rareAction * 2).round();

    // 关注度
    switch (al) {
      case AttentionLevel.L3: break;
      case AttentionLevel.L2:
        wander = (wander * 0.7).round();
        speakBubble = (speakBubble * 0.5).round();
      case AttentionLevel.L1:
        wander = (wander * 0.5).round();
        speakBubble = (speakBubble * 0.3).round();
      case AttentionLevel.L0:
        idleBreath = 0; lookAround = 0; wander = 0; sitDown = 0;
        rareAction = 0; hungryBubble = 0; speakBubble = 0;
        sleep = 100;
    }
  }

  /// 加权随机选择，返回动作名称。
  String pickAction() {
    final total = this.total;
    if (total <= 0) return 'sleep';
    var roll = _rng.nextInt(total);
    for (final entry in [
      ('idleBreath', idleBreath), ('lookAround', lookAround),
      ('wander', wander), ('sitDown', sitDown),
      ('rareAction', rareAction), ('hungryBubble', hungryBubble),
      ('sleep', sleep), ('speakBubble', speakBubble),
    ]) {
      roll -= entry.$2;
      if (roll < 0) return entry.$1;
    }
    return 'idleBreath';
  }
}

class PokeTracker {
  int count = 0;
  double _pokeTimer = 0;
  static const _window = 2.0; // 2秒窗口

  PokeReaction recordPoke({double dt = 0}) {
    _pokeTimer += dt;
    if (_pokeTimer > _window) count = 0;
    count++;
    _pokeTimer = 0;
    if (count >= 10) return PokeReaction.playDead;
    if (count >= 3) return PokeReaction.annoyed;
    if (count >= 1) return PokeReaction.bounce;
    return PokeReaction.none;
  }
}

class UserRhythm {
  final _interactions = <DateTime>[];
  static const _window = Duration(minutes: 5);
  int _freqPerMin = 0;

  void recordInteraction() {
    final now = DateTime.now();
    _interactions.add(now);
    _interactions.removeWhere((t) => now.difference(t) > _window);
    _freqPerMin = _interactions.length;
  }

  int get freqPerMin => _freqPerMin;

  AttentionLevel suggestLevel(AttentionLevel current) {
    if (_freqPerMin > 10) return AttentionLevel.L2;  // 用户忙 → 安静
    if (_freqPerMin < 3 && current == AttentionLevel.L2) return AttentionLevel.L3;
    return current;
  }
}

class DailyMood {
  final double moodSeed;
  final String emoji;
  final String label;

  DailyMood._(this.moodSeed, this.emoji, this.label);

  factory DailyMood.today() {
    final rng = Random(DateTime.now().year * 10000 +
        DateTime.now().month * 100 + DateTime.now().day);
    final seed = 0.5 + (rng.nextDouble() - 0.5) * 0.5; // 0.25-0.75
    if (seed > 0.75) return DailyMood._(seed, '😸', '今天心情超好');
    if (seed < 0.25) return DailyMood._(seed, '😼', '今天是糯糯的小脾气日');
    return DailyMood._(seed, '😊', '普通的一天');
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/services/pet_brain_test.dart
```

预期：全部 PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/pet_brain.dart test/services/pet_brain_test.dart
git commit -m "feat: 新增 PetBrain 行为决策系统

行为权重表 + 5段时段主题 + 3级空闲分层 + 每日心情
+ 用户节奏感知 + 戳宠进化(1/3/10次)。
含 10 个单元测试。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: pet_bubble_manager.dart — 预设气泡管理

**Files:**
- Create: `lib/services/pet_bubble_manager.dart`
- Create: `test/services/pet_bubble_manager_test.dart`

- [ ] **Step 1: 创建测试文件**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/services/pet_bubble_manager.dart';
import 'package:ai_chat/services/pet_brain.dart';

void main() {
  group('PetBubbleManager', () {
    late PetBubbleManager mgr;

    setUp(() => mgr = PetBubbleManager());

    test('气泡池非空', () {
      expect(mgr.totalCount, greaterThan(80));
    });

    test('早晨返回问候类气泡', () {
      final b = mgr.pick(category: 'greeting', period: DayPeriod.morning);
      expect(b, isNotNull);
      expect(b, contains('早安'));
    });

    test('深夜不返回早安', () {
      // 深夜的问候应为晚安类
      final b = mgr.pick(category: 'greeting', period: DayPeriod.night);
      expect(b, isNotNull);
      // 深夜不包含"早安"
      expect(b.contains('早安'), isFalse);
    });

    test('冷却期内返回 null', () {
      final b1 = mgr.pick(category: 'greeting', period: DayPeriod.morning);
      expect(b1, isNotNull);
      // 立即再取同分类 → 应为 null（冷却）
      final b2 = mgr.pick(category: 'greeting', period: DayPeriod.morning);
      expect(b2, isNull);
    });

    test('resetCooldown 后可以再取', () {
      mgr.pick(category: 'greeting', period: DayPeriod.morning);
      mgr.resetCooldown('greeting');
      final b = mgr.pick(category: 'greeting', period: DayPeriod.morning);
      expect(b, isNotNull);
    });

    test('不同分类不共享冷却', () {
      mgr.pick(category: 'greeting', period: DayPeriod.morning);
      final b = mgr.pick(category: 'affection', period: DayPeriod.morning);
      expect(b, isNotNull);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/services/pet_bubble_manager_test.dart
```

预期：FAIL

- [ ] **Step 3: 创建 pet_bubble_manager.dart**

```dart
// Flutter 3.24 / Dart 3.5
import 'dart:math';
import 'pet_brain.dart';

class PetBubbleManager {
  final _rng = Random();
  final _cooldowns = <String, DateTime>{};
  static const _cooldownDuration = Duration(minutes: 2);
  final _lastPick = <String, String>{};

  int get totalCount => _morning.length + _daytime.length + _evening.length +
      _night.length + _hungry.length + _sleepy.length +
      _affection.length + _pokeReactions.length + _surprise.length;

  // ── 时段问候 ──
  static const _morning = [
    '早安~☀️', '新的一天喵！', '主人起床了~', '今天天气不错喵~',
    '早上好！糯糯等你很久了~', '又是元气满满的一天！', '主人今天有什么计划喵？',
    '早起的鸟儿有虫吃~', '糯糯刚醒...还有点困💤', '要加油哦今天！',
  ];

  static const _daytime = [
    '主人在干嘛喵？', '好无聊...', '戳戳我试试喵~', '嗯？有东西在动？',
    '糯糯在想你呢...', '看到主人就开心~ 😸', '摸摸我好嘛...', '喵？那是啥？',
    '主人辛苦了~ ☕', '糯糯会一直陪着你的~',
  ];

  static const _evening = [
    '主人一天辛苦了~', '该休息一下了喵~', '抱抱~', '和糯糯聊聊天叭~',
    '主人今天过得好吗？', '糯糯最喜欢主人了~', '主人笑起来最好看了~',
    '今天想和主人聊天~', '糯糯在这里等你~', '辛苦一天了，放松一下喵~',
  ];

  static const _night = [
    '夜深了，安静陪你~🌙', '主人还不睡吗？', '好困...💤', '晚安喵~',
    '明天见~', '做个好梦喵~', '糯糯先睡了...zzZ', '晚上冷，记得盖被子~',
    '熬夜不好哦...', '主人也早点休息吧~',
  ];

  // ── 状态表达 ──
  static const _hungry = [
    '有点饿了喵~ 🍖', '想吃东西...', '主人有没有零食？', '肚子在叫了...',
    '好饿好饿！', '糯糯想吃鱼~', '该喂糯糯了喵~', '闻到好吃的味道了！',
    '主人~糯糯饿了~', '有没有小鱼干？',
  ];

  static const _sleepy = [
    '糯糯好困...💤', '眼睛睁不开了...', '好想睡觉喵~', 'zzZ...啊！没睡着！',
    '主人我眯一会...', '困到转圈圈...', '电量不足，需要充电💤', '打个哈欠...🥱',
  ];

  // ── 撒娇 ──
  static const _affection = [
    '抱抱~', '主人最好了~ 😸', '糯糯最喜欢主人了~', '想要被摸摸头...',
    '主人~陪糯糯玩嘛~', '不要走...', '喵~抓到你了！', '蹭蹭主人~',
    '主人身上好暖和~', '粘着你！', '只给主人一个人喵~', '嘻嘻~',
    '主人好温柔~', '和主人在一起最开心了~', '想一直被主人抱着~',
  ];

  // ── 回应戳 ──
  static const _pokeReactions = [
    '啊！', '喵~', '干嘛啦', '嗯哼？', '哎呀！', '嘻嘻~', '抓到你了！',
    '戳我干嘛~', '别戳了喵~', '好痒！', '哼！', '再戳生气了哦！',
  ];

  // ── 惊喜（稀有） ──
  static const _surprise = [
    '今天是糯糯的生日喵~🎂', '和主人认识100天啦！', '糯糯今天超开心！✨',
    '啦啦啦~ 🎵', '心情超好喵！', '转圈圈~', '今天是个好日子~',
    '糯糯学会新技能了！', '主人主人！快看我！', '今天运气真好~🍀',
  ];

  /// 根据分类和时段选取气泡。冷却期内返回 null。
  String? pick({String category = 'daytime', DayPeriod period = DayPeriod.afternoon}) {
    // 冷却检查
    if (_cooldowns.containsKey(category)) {
      if (DateTime.now().difference(_cooldowns[category]!) < _cooldownDuration) {
        return null;
      }
    }

    final pool = _getPool(category, period);
    if (pool.isEmpty) return null;

    // 避免连续相同
    String bubble;
    var attempts = 0;
    do {
      bubble = pool[_rng.nextInt(pool.length)];
      attempts++;
    } while (bubble == _lastPick[category] && attempts < 5);

    _lastPick[category] = bubble;
    _cooldowns[category] = DateTime.now();
    return bubble;
  }

  List<String> _getPool(String category, DayPeriod period) {
    switch (category) {
      case 'greeting':
        return switch (period) {
          DayPeriod.morning => _morning,
          DayPeriod.night => _night,
          DayPeriod.evening => _evening,
          _ => _daytime,
        };
      case 'hungry': return _hungry;
      case 'sleepy': return _sleepy;
      case 'affection': return _affection;
      case 'poke': return _pokeReactions;
      case 'surprise': return _surprise;
      default: return _daytime;
    }
  }

  void resetCooldown(String category) => _cooldowns.remove(category);
  void resetAllCooldowns() => _cooldowns.clear();
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/services/pet_bubble_manager_test.dart
```

预期：全部 PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/pet_bubble_manager.dart test/services/pet_bubble_manager_test.dart
git commit -m "feat: 新增 PetBubbleManager 预设气泡管理

100+条气泡 × 5分类(问候/状态/撒娇/回应/惊喜) × 5时段匹配。
2分钟冷却防重复。含 6 个单元测试。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: 集成 — PetOverlayController 接入 PetBrain

**Files:**
- Modify: `lib/services/pet_overlay_host.dart`

**Purpose:** 用 PetBrain 替代现有的 Timer 驱动的空闲行为（`_idleBubbleTimer` / `_idleBehaviorTimer` / `_idleBubbles` 列表）。

- [ ] **Step 1: 修改 pet_overlay_host.dart**

关键改动：在 `start()` 中初始化 PetBrain + BubbleManager，用 PetBrain 的决策循环替代旧的 Timer 空闲行为。

```dart
// 在文件顶部新增 import
import 'pet_brain.dart';
import 'pet_bubble_manager.dart';
import 'pet_agent_core.dart';

// 在 PetOverlayController 类中新增字段
final _brain = BehaviorWeights();
final _bubbleMgr = PetBubbleManager();
final _pokeTracker = PokeTracker();
final _rhythm = UserRhythm();
final _dailyMood = DailyMood.today();
Timer? _brainTimer;
int _idleSeconds = 0;
Timer? _idleSecondTimer;

// 修改 start() 方法中 _startIdleBehavior() 调用
// 将：
//   _startIdleBehavior();
// 替换为：
//   _startBrainLoop();
//   _scheduleIdleSecond();

// 新增方法
void _startBrainLoop() {
  _brainTimer?.cancel();
  _brainTimer = Timer.periodic(const Duration(seconds: 30), (_) {
    if (!_started) return;
    _brainTick();
  });
}

void _scheduleIdleSecond() {
  _idleSecondTimer?.cancel();
  _idleSecondTimer = Timer.periodic(const Duration(seconds: 1), (_) {
    if (!_started) _idleSeconds++;
  });
}

void _brainTick() {
  final now = DateTime.now();
  final s = _controller?.state;
  final al = PetAgentCore.shared?.attentionLevel ?? AttentionLevel.L3;

  _brain.applyContext(
    hour: now.hour,
    hunger: s?.hunger ?? 80,
    energy: s?.energy ?? 80,
    mood: (s?.mood ?? 50) / 100,
    al: al,
  );

  // 每日心情偏移
  final moodMod = _dailyMood.moodSeed;
  _brain.wander = (_brain.wander * moodMod * 2).round();
  _brain.speakBubble = (_brain.speakBubble * moodMod * 2).round();

  // 空闲分层
  final tier = IdleTierExt.fromIdleSeconds(_idleSeconds);

  final action = _brain.pickAction();
  switch (action) {
    case 'wander':
      final maxX = 1080.0; // 实际应从屏幕获取
      final maxY = 1920.0;
      final rng = Random();
      final tx = rng.nextDouble() * maxX * 0.8 + maxX * 0.1;
      final ty = rng.nextDouble() * maxY * 0.6 + maxY * 0.2;
      _cmd('moveTo', {'x': tx, 'y': ty, 'speed': 'walk'});
      _cmd('playAnim', {'anim': 'walk'});

    case 'sitDown':
      _cmd('playAnim', {'anim': 'sit'});
      // 2 分钟后站起
      Future.delayed(const Duration(minutes: 2), () {
        _cmd('playAnim', {'anim': 'idle'});
      });

    case 'rareAction':
      if (_dailyMood.moodSeed > 0.6) {
        _cmd('playAnim', {'anim': 'idle', 'emotionSpeed': 1.5});
      }
      final b = _bubbleMgr.pick(category: 'surprise', period: DayPeriodExt.fromHour(now.hour));
      if (b != null) _cmd('showBubble', {'text': b, 'durationMs': 4000});

    case 'hungryBubble':
      final b = _bubbleMgr.pick(category: 'hungry', period: DayPeriodExt.fromHour(now.hour));
      if (b != null) _cmd('showBubble', {'text': b, 'durationMs': 3000});

    case 'speakBubble':
      final b = _bubbleMgr.pick(category: 'affection', period: DayPeriodExt.fromHour(now.hour));
      if (b != null) _cmd('showBubble', {'text': b, 'durationMs': 3000});

    case 'sleep':
      _cmd('playAnim', {'anim': 'sleeping'});

    default:
      // idleBreath / lookAround → 保持 idle
      if (tier == IdleTier.tier1) {
        // 呼吸缩放由 Kotlin 端物理引擎处理
      } else if (tier == IdleTier.tier2) {
        // 微动由 FrameBlender 处理
      }
  }
}
```

完整改动见注：由于文件较长，核心是将 `_startIdleBehavior()` / `_stopIdleBehavior()` / `_scheduleIdleBubble()` / `_scheduleIdleAction()` / `_showBubbleWithDismiss()` 替换为上述 PetBrain 驱动的决策循环。`_cmd('showBubble')` 和 `_cmd('playAnim')` 保持不变，因为 PetForegroundService 的 handleCommand 已支持这些命令。`_cmd('moveTo')` 是新增的命令。

- [ ] **Step 2: 验证编译**

```bash
flutter analyze lib/services/pet_overlay_host.dart
```

预期：零新增 error

- [ ] **Step 3: 运行全部现有测试确认回归**

```bash
flutter test
```

预期：现有 252+ 测试全部通过

- [ ] **Step 4: Commit**

```bash
git add lib/services/pet_overlay_host.dart
git commit -m "refactor: PetOverlayController 接入 PetBrain 决策系统

PetBrain 替代旧 Timer 空闲行为（_idleBubbleTimer/_idleBehaviorTimer）。
新增：权重表决策循环(30s) + 时段主题 + 每日心情 + 戳宠进化。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: 集成 — main.dart 注册 BubbleManager

**Files:**
- Modify: `lib/main.dart`

**Purpose:** 注册 PetBubbleManager 到 MultiProvider（轻量，仅 5 行）。

- [ ] **Step 1: 修改 main.dart**

在 `MultiProvider` 的 `providers` 列表中追加：

```dart
ChangeNotifierProvider(create: (_) { final s = PetBubbleManager(); return s; }),
```

完整 diff 位置：`lib/main.dart` 约第 53 行，`PetDiaryService` 注册之后。

- [ ] **Step 2: 验证编译 + 测试**

```bash
flutter analyze lib/main.dart && flutter test
```

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat: main.dart 注册 PetBubbleManager

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: 新增动画帧（walk + sit）

**Files:**
- 创建目录: `android/app/src/main/assets/pet_frames/walk/`
- 创建目录: `android/app/src/main/assets/pet_frames/sit/`

**Purpose:** 用 AI 生成走和坐两种新动画帧，使宠物可以自由移动和坐下。

**⚠️ 注意：此任务需要用户手动操作 AI 工具。步骤 1-3 为 AI 生成指引，步骤 4-5 为集成验证。**

- [ ] **Step 1: 使用 ComfyUI + AnimateDiff 生成 walk 帧**

工作流：
1. 加载 ComfyUI + AnimateDiff 工作流
2. ControlNet 参考图：选取 `assets/pet_frames/idle/frame_00.png` 作为角色参考
3. Prompt（复制到 ComfyUI positive prompt 框）：
```
A cute cartoon cat character sprite sheet for a desktop pet app.
Style: 2D cartoon, soft rounded lines, warm color palette (orange/cream tabby cat).
The character shown in a walking cycle, side view.
8 frames, each frame ~256x256 pixels, transparent background.
Consistent lighting, same character design across all frames.
The walking cycle should loop smoothly — frames should connect seamlessly.
Character design reference: small chibi cat with big eyes, short limbs, fluffy tail.
Simple animation, minimal background, sprite sheet format.
```
4. Negative prompt: `blurry, inconsistent character, different style, background, shadows on ground`
5. 设置帧数=8，输出格式=PNG 序列
6. 手动检查帧间一致性和透明背景
7. 导出到临时目录

- [ ] **Step 2: 使用 ComfyUI + AnimateDiff 生成 sit 帧**

同上流程，Prompt 替换为：
```
A cute cartoon cat character sprite sheet for a desktop pet app.
Style: 2D cartoon, soft rounded lines, warm color palette (orange/cream tabby cat).
The character transitioning from standing to sitting pose, side view.
6 frames, each frame ~256x256 pixels, transparent background.
Consistent with the same character design as the reference image.
Animation: cat lowers body, folds legs, settles into seated position, tail wraps around.
Simple animation, sprite sheet format, transparent background.
```

- [ ] **Step 3: 重命名并放置帧文件**

生成后的帧文件复制到 Android assets 目录：

```bash
# 假设生成的文件在 ~/comfyui/output/walk/ 下
mkdir -p android/app/src/main/assets/pet_frames/walk
mkdir -p android/app/src/main/assets/pet_frames/sit

# walk: 8 帧
cp ~/comfyui/output/walk/frame_*.png android/app/src/main/assets/pet_frames/walk/
# 重命名为 frame_00.png ~ frame_07.png（按时间顺序）

# sit: 6 帧
cp ~/comfyui/output/sit/frame_*.png android/app/src/main/assets/pet_frames/sit/
# 重命名为 frame_00.png ~ frame_05.png
```

- [ ] **Step 4: 验证帧文件格式**

```bash
ls -la android/app/src/main/assets/pet_frames/walk/
ls -la android/app/src/main/assets/pet_frames/sit/
```

预期：walk 目录有 8 个 PNG 文件，sit 目录有 6 个 PNG 文件。每个文件应在 100-200KB 范围内。

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/assets/pet_frames/walk/
git add android/app/src/main/assets/pet_frames/sit/
git commit -m "feat: AI 生成 walk(8帧) + sit(6帧) 动画帧

ComfyUI + AnimateDiff，以 idle frame_00 为 ControlNet 参考。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: 全量测试 + 手动验证

**Files:**
- 无新建文件

- [ ] **Step 1: 运行全部 Flutter 测试**

```bash
flutter test
```

预期：全部 252+ 测试通过，新增 16 个测试通过

- [ ] **Step 2: 运行 flutter analyze**

```bash
flutter analyze
```

预期：零新增 error

- [ ] **Step 3: 运行 Android 编译**

```bash
cd android && ./gradlew :app:assembleDebug
```

预期：BUILD SUCCESSFUL

- [ ] **Step 4: 手动验证清单**

| # | 场景 | 预期 |
|---|------|------|
| 1 | 启动宠物 | 宠物出现，idle 动画流畅播放 |
| 2 | 点击宠物 | 弹跳反馈 + MiniChat 弹出 |
| 3 | 拖拽宠物 | 跟随手指 + 松手惯性飞 + 落地弹跳 |
| 4 | 3 秒不碰 | 宠物穿透（点击穿过它） |
| 5 | 空闲 20s+ | 微动出现（眨眼/耳朵动） |
| 6 | 空闲 90s+ | 坐下或睡觉 |
| 7 | 连戳 3 次 | "别戳了喵~" + 跳起 |
| 8 | 发送消息 | talking 动画 + 流式气泡 |
| 9 | 屏幕关闭 | 动画停止，亮屏恢复 |
| 10 | 透明背景 | 宠物悬浮时无黑边/黑块 |

- [ ] **Step 5: Commit 最终验证结果**

```bash
git add -A
git commit -m "test: 全量测试通过 (252+16) + flutter analyze 零新增

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## 架构回顾

```
实施前：                          实施后：
PetForegroundService (360行)      PetForegroundService (~200行)
├── ImageView (15fps)             ├── PetView (60fps) 🆕
├── Handler.postDelayed            │   ├── PetPhysics 🆕
├── loadedAnims                    │   ├── FrameBlender 🆕
├── curAnim/animRunnable           │   └── BubbleAnimator 🆕
├── bubbleText (TextView)          ├── loadAllFrames
├── emojiText (TextView)           └── handleCommand (扩展)
└── handleCommand

PetOverlayController               PetOverlayController
├── _idleBubbleTimer               ├── PetBrain 🆕
├── _idleBehaviorTimer             ├── PetBubbleManager 🆕
└── _idleBubbles (18条)            └── _brainTimer + _idleSecondTimer
```

## 风险与回滚

- **低端机掉帧:** `LAYER_TYPE_HARDWARE` 改为 `LAYER_TYPE_SOFTWARE` + 30fps
- **AI 帧一致性差:** 用更多 idle 帧做 ControlNet 多图参考
- **物理 bug:** PetPhysics 纯数据类，可独立单元测试
- **回滚:** 改动集中在 PetForegroundService 和 PetOverlayController，git revert 即可恢复旧版本
