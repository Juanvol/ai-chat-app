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
