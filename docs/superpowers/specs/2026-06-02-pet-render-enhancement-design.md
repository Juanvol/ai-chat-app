# 弗糯糯宠物渲染增强 — 设计规格说明

> **日期:** 2026-06-02 | **状态:** 待审查
> **关联:** [2026-05-30-pet-design.md](2026-05-30-pet-design.md) · [2026-05-30-pet-agent-design.md](2026-05-30-pet-agent-design.md) · [2026-05-30-minichat-agent-bridge-design.md](2026-05-30-minichat-agent-bridge-design.md)
> **参考产品:** Chatty (Godot) · Shimeji · VPet-Simulator · DyberPet · Compapet

---

## 一、问题陈述

当前弗糯糯宠物悬浮窗存在以下问题（用户反馈："像一张图片贴在上面"）：

| # | 问题 | 根因 |
|---|------|------|
| 1 | 动画卡顿不流畅 | ImageView + Handler 15fps，无帧间过渡 |
| 2 | 像贴图 | 无物理感（重力/惯性/弹性），位置固定不动 |
| 3 | 交互生硬 | 点击无视觉反馈，气泡闪现消失 |
| 4 | 不生动 | 无自主移动、无空闲分层、无情绪表达 |
| 5 | 性能差 | 无帧率管理、无省电策略 |
| 6 | 视觉效果差 | 动画硬切换、不跟随方向、无微动细节 |

## 二、设计目标

1. **活物感** — 全屏自由移动 + 物理引擎 + 弹性挤压，不再"像贴图"
2. **情绪表达** — 情绪变体动画 + 微动 overlay + 方向感知
3. **智能行为** — 时段主题 + 每日心情 + 空闲分层 + 用户节奏感知
4. **细腻交互** — 触控反馈动画 + 连戳升级 + 悬停半透明
5. **无感存在** — 3s空闲后点击穿透，工作时不影响操作
6. **零膨胀** — 不引入任何外部引擎/依赖，APK 不增加

## 三、行业参考精华萃取

| 来源 | 采用的设计 | 不采用的原因 |
|------|-----------|-------------|
| **Chatty (Godot)** | 速度驱动动画、RNG决策(3-8s)、拖拽惯性数组、边界弹回、点击穿透 | Godot引擎（APK膨胀） |
| **Shimeji** | 坐→站循环、概率状态转换、视线跟随光标 | 窗口攀爬（Android不可靠） |
| **VPet-Simulator** | 三级空闲分层、稀有动画彩票(3%)、情绪变体 | MOD系统（过度工程） |
| **DyberPet** | 行为权重表+冷却、时段主题、上下文感知 | — |
| **Compapet** | 连戳升级反应、壁面滑落、惯性飞行 | 便便系统（不适用） |

**明确不引入:** Desktop Goose 破坏行为（违背温馨定位）、eSheep 多宠（单人设）、Weyrdlets 内置Todo（角色越界）。

## 四、架构总览

```
Android 进程（单 Flutter 引擎）
│
├── Dart 端 (引擎 #1)
│   ├── PetAgentCore (大脑) — 不改！AI决策/记忆/Token/主动建议
│   ├── PetBrain 🆕 — 行为决策（移动/动画/空闲/时段）
│   ├── BubbleManager 🆕 — 100条预设气泡 × 时段 × 情绪
│   ├── PetController — 不改！身体状态（hunger/mood/energy 衰减）
│   └── PetOverlayController — 改！接入 PetBrain，替代 Timer 空闲行为
│
├── Kotlin 端 (PetForegroundService)
│   ├── PetView 🆕 — Custom View + 硬件层，60fps Canvas 渲染
│   ├── PetPhysics 🆕 — 轻量物理引擎（重力/碰撞/弹性/惯性/摩擦/壁面）
│   ├── FrameBlender 🆕 — 帧插值混合 + 情绪变体 + 微动 overlay
│   ├── BubbleAnimator 🆕 — 弹性气泡（淡入+缩放+自动消失）
│   └── TouchFeedback 🆕 — 触控波纹 + 连戳计数
│
└── 通信: MethodChannel 双向协议（Dart↔Kotlin）
```

### 与现有 Agent Spec 的关系

```
PetAgentCore (大脑 — 不改)          PetBrain + PetView (表达 — 本次改动)
├── 感知：屏幕内容/时间/用户状态      ├── 宠物走到哪
├── 决策：要不要说话/说什么           ├── 播什么动画
├── LLM：调 AI 生成回复              ├── 物理怎么动
├── 记忆：用户画像/知识积累           ├── 气泡怎么弹出
├── Token：三层过滤+额度控制          ├── 触控怎么反馈
└── 主动建议：截图分析+场景触发       └── 空闲时干什么
```

PetBrain 读取 PetAgentCore 的关注度等级（L3→多动、L0→不动）和 PetController 的身体状态（hunger/energy→影响行为权重），但不修改它们。

## 五、渲染系统

### 5.1 方案选择

**Custom View + LAYER_TYPE_HARDWARE**（采用）

| 特性 | 方案评分 | 原因 |
|------|---------|------|
| 透明背景 | ✅ | 普通 View，天然透明 |
| 60fps | ✅ | GPU 硬件层接管绘制 |
| 额外内存 | ✅ | 0（GPU 管理纹理缓存） |
| 帧延迟 | ✅ | 0（不经过 SurfaceTexture） |
| Alpha 动画 | ✅ | View.setAlpha() 原生支持 |
| 复杂度 | ✅ | ~400 行 Kotlin |

**为什么不选 TextureView:** TextureView 为外部图像源（Camera/视频解码/OpenGL）设计，需要独立 Surface + 缓冲队列 + GPU 纹理拷贝。本次场景是 Kotlin 代码主动绘 Bitmap，不需要这些。

**为什么不选 SurfaceView:** 悬浮窗里透明渲染不可靠（独立窗口层 + z-ordering 冲突）。

### 5.2 PetView 核心设计

```kotlin
// Flutter 3.24 / Dart 3.5 — Android Kotlin 层
class PetView(context: Context) : View(context) {
    init {
        setLayerType(LAYER_TYPE_HARDWARE, null)
        setBackgroundColor(Color.TRANSPARENT)
    }

    private val renderLoop = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            physics.update(deltaTime)
            invalidate()  // 触发硬件层重绘
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(0, PorterDuff.Mode.CLEAR)  // 透明
        canvas.save()
        // 方向翻转（朝移动方向）
        if (facingLeft) canvas.scale(-1f, 1f, centerX, centerY)
        // 弹性挤压（落地效果）
        canvas.scale(squashX, squashY, centerX, centerY)
        // 绘制精灵帧
        frameBlender.drawCurrentFrame(canvas, x, y)
        // 微动 overlay（眨眼/耳朵）
        microOverlay.draw(canvas)
        canvas.restore()
        // 气泡
        bubble.draw(canvas)
        // 落地粒子
        particleSystem.draw(canvas)
    }
}
```

### 5.3 透明保障（三条保险）

1. **窗口级** — `WindowManager.LayoutParams` 保持 `PixelFormat.TRANSLUCENT`
2. **View 级** — `setBackgroundColor(Color.TRANSPARENT)`
3. **Canvas 级** — 每帧 `canvas.drawColor(0, PorterDuff.Mode.CLEAR)`

### 5.4 无感存在：点击穿透

空闲 3 秒后自动切换为穿透模式：
```kotlin
fun enablePassthrough() {
    val lp = rootView.layoutParams as WindowManager.LayoutParams
    lp.flags = lp.flags or FLAG_NOT_TOUCHABLE
    windowManager.updateViewLayout(rootView, lp)
}
```
鼠标/手指靠近宠物 50px → 恢复可交互。

### 5.5 视线跟随

每 3 秒检测光标位置 → 如果光标在屏幕内，眼球/头部微偏 ±5°（canvas.drawBitmap 带微小旋转）。

### 5.6 任务栏感知

检测可用屏幕区域（`Resources.getSystem().displayCutout` + 系统 insets），底部边界 = 任务栏顶部而非物理屏幕底部。

## 六、物理引擎

### 6.1 物理公式（~180 行 Kotlin）

| 属性 | 公式/值 | 说明 |
|------|---------|------|
| 重力加速度 | `vy += 980 * dt` | 被扔后下落 |
| 边界碰撞 | `if (x < 0) { x=0; vx *= -0.6 }` | 碰边弹回 |
| 弹性挤压 | `squashX = 1 + abs(vx)/2000; squashY = 1/squashX` | 落地变扁，跳起变长 |
| 拖拽惯性 | `vx = (x - prevX) / dt` | 松手继续飞 |
| 摩擦力 | `vx *= 0.95; vy *= 0.95` | 自然减速 |
| 壁面滑落 | `if (碰竖边) { vx=0; vy 保持不变 }` | 沿墙滑下 |

### 6.2 新增物理特性

| 特性 | 实现 | 来源 |
|------|------|------|
| 下落终点=任务栏 | `maxY = screenHeight - taskbarHeight - petHeight` | Chatty |
| 边缘粘停 0.5s | 碰边→暂停+挤压变形→0.5s后弹回 | Shimeji |
| 落地粒子 | 落地时生成 3-5 个随机方向小点（Alpha 衰减 200ms） | VPet |
| 壁面滑落 | 碰竖边时 vx=0, vy 不变 | Compapet |

## 七、动画系统

### 7.1 帧动画（阶段一：5 套）

| 动画 | 帧数 | 帧间隔 | 触发 | 来源 |
|------|------|--------|------|------|
| idle | 27帧 | 67ms | 无事件 | ✅ 已有 |
| walk | 8-12帧 | 80ms | 移动中 | 🆕 AI 生成 |
| sit | 4-6帧 | 150ms | 到达后休息 | 🆕 AI 生成 |
| sleeping | 5帧 | 500ms | 30min+ 无交互 | ✅ 已有 |
| talking | 16帧 | 67ms | MiniChat 对话 | ✅ 已有 |

**阶段二（后续）：** run(8帧) / jump(6帧) / eat(8帧) / happy(6帧)

### 7.2 帧插值混合（FrameBlender）

A→B 动画切换时，不是硬切，而是交叉淡入淡出 200ms。

### 7.3 情绪变体

同一套帧图 + 不同播放参数模拟情绪：
- 开心：播放速度×1.2 + 饱和度+10%
- 伤心：播放速度×0.8 + 灰度+20%
- 兴奋：播放速度×1.5 + 缩放微弹

### 7.4 微动 Overlay

独立于基础动画的微小动作，随机叠加：
- 眨眼（概率 15%/5s）
- 耳朵微动（概率 10%/3s）
- 尾巴轻摆（概率 20%/4s，仅 idle 状态）

### 7.5 方向翻转

宠物朝移动方向：`canvas.scale(-1f, 1f, centerX, centerY)`

### 7.6 AI 帧生成规格

**推荐工具:** ComfyUI + AnimateDiff（用现有 27 帧 idle 作为 ControlNet 参考图）

**walk prompt 模板:**
```
A cute cartoon cat character sprite sheet for a desktop pet app.
Style: 2D cartoon, soft rounded lines, warm color palette (orange/cream tabby cat).
The character shown in a walking cycle.
8 frames, side view, each frame ~256x256 pixels.
Transparent background. Consistent lighting, same character design across all frames.
The walking cycle should loop smoothly.
Character design reference: small chibi cat with big eyes, short limbs, fluffy tail.
```

**sit prompt 模板:**
```
A cute cartoon cat character sprite sheet for a desktop pet app.
Style: 2D cartoon, soft rounded lines, warm color palette (orange/cream tabby cat).
The character transitioning from standing to sitting pose.
6 frames, side view, each frame ~256x256 pixels.
Transparent background. Consistent with the same character design.
Animation: cat lowers body, folds legs, settles into seated position, tail wraps around.
```

**帧文件命名规范:**
```
assets/pet_frames/
├── idle/        frame_00.png ~ frame_52.png  (27帧, ✅已有)
├── walk/        frame_00.png ~ frame_07.png  (8帧,  🆕)
├── sit/         frame_00.png ~ frame_05.png  (6帧,  🆕)
├── sleeping/    frame_00.png ~ frame_16.png  (5帧, ✅已有)
├── talking/     frame_00.png ~ frame_60.png  (16帧, ✅已有)
├── run/         frame_00.png ~ frame_07.png  (8帧,  🔮后续)
├── jump/        frame_00.png ~ frame_05.png  (6帧,  🔮后续)
└── eat/         frame_00.png ~ frame_07.png  (8帧,  🔮后续)
```

## 八、行为系统（PetBrain）

### 8.1 空闲分层（Idle Tiers）

| 层级 | 时间阈值 | 动画 | 微动 |
|------|---------|------|------|
| Tier 1: 主空闲 | 0-20s | idle 循环 | 呼吸缩放 (1.0↔1.02, 3s周期) |
| Tier 2: 次空闲 | 20-90s | idle + 微动作 | 歪头/晃尾/环顾（概率触发） |
| Tier 3: 深度空闲 | 90s+ | sit 或 sleeping | 稀有动画彩票(3%/min) |

### 8.2 行为权重表

```dart
class BehaviorWeights {
  int idleBreath = 50;
  int lookAround = 20;
  int wander = 15;
  int sitDown = 10;
  int rareAction = 5;

  void applyContext(int hour, int hunger, int energy,
                    double mood, AttentionLevel al) {
    // 深夜
    if (hour >= 23 || hour < 7) {
      sleep *= 3.0; wander *= 0.3;
    }
    // 饿了
    if (hunger < 30) hungryBubble *= 4.0;
    // 累了
    if (energy < 20) { sitDown *= 2.5; wander *= 0.2; }
    // 关注度
    if (al == L1) { wander *= 0.5; speak *= 0.3; }
    if (al == L0) { 全部归零除了休眠; }
  }
}
```

### 8.3 五段时段主题

| 时段 | 时间 | 主题 | 权重偏移 |
|------|------|------|---------|
| 🌅 早晨 | 6-9 | 活力充沛 | lookAround×2, 稀有动画×2 |
| ☀️ 上午 | 9-12 | 安静陪伴 | idleBreath×1.5, wander×0.5 |
| 🌤 下午 | 12-18 | 轻松调皮 | wander×1.5, 稀有动画×1.5 |
| 🌆 傍晚 | 18-22 | 粘人撒娇 | 气泡频率×2, sitDown×2 |
| 🌙 深夜 | 22-6 | 安静休眠 | sleep×3, 全部×0.3 |

### 8.4 每日心情

每日随机 moodSeed（±25%），全天所有行为权重受此偏移影响。状态卡片显示今日心情 emoji：
- >75%: 😸（今天心情超好）
- 25-75%: 😊（普通的一天）
- <25%: 😼（今天是糯糯的小脾气日）

### 8.5 用户节奏感知

检测最近 5 分钟内的用户交互频率：
- 高频（>10次/分钟）→ 自动降 L2（安静陪伴，用户在忙）
- 中频（3-10次/分钟）→ 保持 L3
- 低频（<3次/分钟）→ 可主动搭话（L3）

### 8.6 戳宠进化

| 连戳次数 | 反应 | 冷却 |
|---------|------|------|
| 1次 | "喵~" + 弹跳 | 无 |
| 3次 (2s内) | "啊！别戳了喵~" + 跳起+晕眩 | 5s |
| 10次 (10s内) | 装死 3s + 复活 + "糯糯生气了！" | 30s |

## 九、交互系统

### 9.1 手势识别

| 交互 | 判定条件 | Kotlin 反馈 | Dart 行为 |
|------|---------|------------|----------|
| 单击 | <300ms, 位移<5px | 缩放弹跳 1.0→1.15→1.0 + 触控波纹 | 聊天 + talking 动画 |
| 双击 | 两次单击<400ms | 旋转 360° + 跳起 | 打开主 App |
| 长按 | ≥500ms, 位移<10px | 放大 + 菜单弹出 | 喂食/玩耍 |
| 拖拽 | 移动>15px | 跟随手指 + 松手惯性飞行 | 保存坐标 |
| 悬停 1s | ACTION_HOVER | alpha→0.3 | 不遮挡内容 |

### 9.2 连戳升级（见 8.6）

### 9.3 点击穿透

空闲 3s → `FLAG_NOT_TOUCHABLE`。手指靠近 50px → 恢复可交互。

## 十、气泡系统（BubbleManager）

### 10.1 预设气泡池（100+ 条，5 类 × 5 时段）

| 类别 | 数量 | 示例 |
|------|------|------|
| 问候 | 20条 | 早晨"早安~☀️" / 下午"主人在干嘛喵？" |
| 状态表达 | 20条 | 饿了"有点饿了喵~🍖" / 困了"糯糯好困...💤" |
| 撒娇 | 20条 | "抱抱~" "主人最好了~ 😸" |
| 回应戳 | 15条 | 被戳"啊！" "干嘛啦" "嘻嘻~" |
| 惊喜 | 25条 | 生日"今天是糯糯的生日喵~🎂" / 100天"和主人认识100天啦！" |

Agent 主动建议仍通过 PetAgentCore 现有逻辑触发。

### 10.2 气泡动画

替换 TextView VISIBLE/GONE 硬切：
- 弹出：Alpha 0→1 (200ms) + Scale 0→1.1→1.0 (300ms)
- 消失：Alpha 1→0 (200ms) + TranslateY 0→-20 (200ms)

## 十一、性能与省电

| 条件 | 帧率 | 行为 | 来源 |
|------|------|------|------|
| 屏幕亮 + 正常 | 60fps | 全帧动画 + 物理 | — |
| 电量<15% | 15fps | 停动画、静态帧 | Pet spec §8.2 |
| 屏幕关闭 | 0fps | 暂停渲染循环 | Pet spec §8.2 |
| L0 休眠 | 0fps | 停止一切 | Agent spec §4 |
| 电话/短信 | 30fps | 缩至 0.3x，挂断 5s 恢复 | Pet spec §8.4 |

## 十二、命令协议 v2

### Dart → Kotlin

| 方法 | 参数 | 说明 |
|------|------|------|
| `moveTo` | `{x, y, speed:"walk\|run"}` | 命令宠物移动到屏幕坐标 |
| `playAnim` | `{anim:"idle\|walk\|sit\|...", emotionVariant?}` | 播放指定动画+情绪变体 |
| `showBubble` | `{text, durationMs, category?}` | 弹性弹出气泡 |
| `setPassthrough` | `{enabled:bool}` | 开关点击穿透 |
| `setFacing` | `{left:bool}` | 翻转朝向 |

### Kotlin → Dart

| 方法 | 参数 | 说明 |
|------|------|------|
| `onTouch` | `{type, x, y}` | 用户触控事件 |
| `onArrive` | `{x, y}` | 到达目标位置 |
| `onAnimEnd` | `{anim}` | 一次性动画播完（循环不发） |
| `onPokeCount` | `{count}` | 连戳计数 |

## 十三、文件变更清单

### 新建（6 个）

| # | 文件 | 职责 | 行数 |
|---|------|------|------|
| 1 | `android/.../PetView.kt` | Custom View + 硬件层渲染 + 视线跟随 + 方向翻转 | ~400 |
| 2 | `android/.../PetPhysics.kt` | 轻量物理引擎（6 公式 + 壁面 + 粒子 + 边缘粘停） | ~180 |
| 3 | `android/.../FrameBlender.kt` | 帧插值混合 + 情绪变体 + 微动 overlay | ~120 |
| 4 | `android/.../BubbleAnimator.kt` | 弹性气泡动画（弹入+淡出） | ~100 |
| 5 | `lib/services/pet_brain.dart` | 行为决策（权重表 + 时段主题 + 空闲分层 + 戳宠进化） | ~280 |
| 6 | `lib/services/pet_bubble_manager.dart` | 100+ 条预设气泡 × 时段 × 情绪分类 | ~120 |

### 修改（3 个）

| # | 文件 | 改动 | 行数变化 |
|---|------|------|---------|
| 1 | `android/.../PetForegroundService.kt` | PetView 替代 ImageView + 新增 handleCommand(moveTo/passthrough) + 触控升级 | 360→~200（简化） |
| 2 | `lib/services/pet_overlay_host.dart` | 接入 PetBrain 替代 Timer 空闲行为 | +60 |
| 3 | `lib/main.dart` | BubbleManager 注册 | +5 |

**总代码量:** ~1200 行新增/修改（Kotlin ~800 + Dart ~400），零外部依赖。

## 十四、与现有系统兼容

| 现有模块 | 影响 | 说明 |
|---------|------|------|
| PetAgentCore | **不改** | 大脑层完全不动 |
| PetAiService | **不改** | 截图分析、主动建议原样保留 |
| PetController | **不改** | 身体状态机原样保留 |
| MiniChat | **不改** | Agent 桥通信路径不变 |
| PetForegroundService | **重构** | ImageView→PetView，handleCommand 扩展 |
| PetOverlayController | **增强** | 接入 PetBrain，旧空闲行为代码移除 |
| EngineBridge | **不改** | 通信桥原样保留 |
| 所有屏幕/Service | **不改** | UI 层不动 |

## 十五、测试策略

### 新增测试（6+ 个）

| # | 文件 | 验证点 |
|---|------|--------|
| 1 | `test/services/pet_brain_test.dart` | 权重表计算正确性 |
| 2 | `test/services/pet_brain_test.dart` | 时段主题切换 |
| 3 | `test/services/pet_brain_test.dart` | 戳宠进化逻辑 |
| 4 | `test/services/pet_brain_test.dart` | 空闲分层推进 |
| 5 | `test/services/pet_bubble_manager_test.dart` | 气泡分类 + 时段匹配 |
| 6 | `test/services/pet_bubble_manager_test.dart` | 冷却后不重复 |

### 回归约束

现有全部测试（252+）必须通过。`flutter analyze` 零新增 error。

## 十六、实施顺序

| 阶段 | 内容 | 预估 |
|------|------|------|
| **1. PetView + PetPhysics** | Custom View 渲染 + 轻量物理引擎 + 触控升级 | Day 1-2 |
| **2. FrameBlender + BubbleAnimator** | 帧插值混合 + 情绪变体 + 微动 + 弹性气泡 | Day 2-3 |
| **3. PetBrain** | 行为权重表 + 时段主题 + 空闲分层 + 戳宠进化 | Day 3-4 |
| **4. PetBubbleManager** | 100 条预设气泡 + 时段匹配 | Day 4 |
| **5. 集成** | PetForegroundService 重构 + PetOverlayController 接入 | Day 4-5 |
| **6. AI 帧生成** | 用 ComfyUI + AnimateDiff 生成 walk/sit 帧 | Day 5（并行） |
| **7. 测试 + 打磨** | 单元测试 + 手动验证 + 性能测试 | Day 5-7 |

## 十七、关键风险

| # | 风险 | 对策 |
|---|------|------|
| 1 | Custom View 硬件层在低端机掉帧 | 降级：LAYER_TYPE_SOFTWARE + 30fps |
| 2 | AI 帧生成角色一致性差 | 用现有 27 帧 idle 做 ControlNet 参考 |
| 3 | 物理手写 bug | 6 个公式简单可测，单元测试覆盖 |
| 4 | 悬浮窗穿透后无法唤醒 | 通知栏保留"关闭宠物"按钮 |
| 5 | Choreographer 在后台暂停 | 屏幕关闭时停止回调，亮屏恢复 |

---

*文档结束 — 待用户审查通过后进入 writing-plans 阶段*
