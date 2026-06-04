# Agent 集成 3 线接线 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 3 根 MethodChannel 线接通 Flutter Agent 层与 Android 原生浮窗层，让宠物动画响应 AI 状态、内在状态、用户触碰。

**Architecture:** 复用现有 3 个 MethodChannel（pet_service / pet_overlay / pet_agent_bridge），在已有模块回调中插入动画/气泡指令。不改架构，只加回调。

**Tech Stack:** Flutter 3.24 / Dart 3.5 / Kotlin / Android WindowManager

---

## 文件结构

| 文件 | 职责 | 改动类型 |
|------|------|----------|
| `pubspec.yaml:4` | 版本号 1.0.0+1 → 1.1.0+2 | 修改 |
| `CHANGELOG.md` | 新文件：版本发布记录 | 新建 |
| `lib/services/pet/pet_agent_core.dart` | Wire 1：LLM 阶段→动画 | 修改 |
| `lib/services/pet/pet_overlay_host.dart` | Wire 2：状态变更→动画订阅 | 修改 |
| `android/.../PetForegroundService.kt` | Wire 3：原生 Dialog 聊天 | 修改 |

---

### Task 1: 版本号 + CHANGELOG

**Files:**
- Modify: `pubspec.yaml:4`
- Create: `CHANGELOG.md`

- [ ] **Step 1: 更新 pubspec.yaml 版本号**

```yaml
version: 1.1.0+2
```

- [ ] **Step 2: 创建 CHANGELOG.md**

```markdown
# Changelog

## 1.1.0+2 — 2026-06-04

### Added
- Agent 集成：LLM 处理状态实时映射为宠物动画（run/talking/wave/failed）
- 状态机联动：饥饿/困倦/开心状态自动同步到原生浮窗动画和气泡
- 桌面交互：点击浮窗宠物弹出迷你聊天对话框

### Changed
- 目录重构：services 拆分为 app/ + pet/，screens/widgets 拆出 pet/ 子目录
- Lint 规则严格化：新增 60+ Dart lint 规则

### Fixed
- 宠物交互：浮窗从全屏 MATCH_PARENT 改为 WRAP_CONTENT 小窗模式
- 宠物下坠：vy 摩擦力始终生效，漫步到达清零速度
```

- [ ] **Step 3: 提交**

```bash
git add pubspec.yaml CHANGELOG.md
git commit -m "chore: bump version to 1.1.0+2, add CHANGELOG"
```

---

### Task 2: Wire 1 — LLM 流 → 原生动画

**Files:**
- Modify: `lib/services/pet/pet_agent_core.dart:489-530`

**原理：** `handleChatRequest()` 已在 main.dart 中被 MethodChannel 调用。在其内部插入对 `pet_overlay` channel 的调用，让原生层播放动画。

- [ ] **Step 1: 在文件顶部新增 MethodChannel 常量**

在 `lib/services/pet/pet_agent_core.dart` 的 import 区域之后、`enum AttentionLevel` 之前添加：

```dart
/// 原生浮窗动画控制通道（与 PetOverlayController 共用）
const _overlayChannel = MethodChannel('com.example.deepseek_chat/pet_overlay');
```

- [ ] **Step 2: 修改 handleChatRequest() 注入动画调用**

将 `lib/services/pet/pet_agent_core.dart` 第 489-502 行的 `handleChatRequest()` 替换为：

```dart
  /// 处理引擎 #2 通过 MethodChannel 发来的聊天请求
  Future<void> handleChatRequest(
    String userText, {
    List<Map<String, dynamic>> history = const [],
    int requestId = 0,
  }) async {
    PetLogger().info('Agent', 'handleChatRequest rid=$requestId len=${userText.length}');

    // ── Wire 1: 开始处理 → run 动画 + 思考气泡 ──
    _sendOverlayCmd('playAnim', {'anim': 'run'});
    _sendOverlayCmd('showBubble', {'text': '正在思考...', 'durationMs': 5000});
    bool firstChunkSent = false;

    await chatStream(
      userText: userText,
      history: history,
      onChunk: (fullText) {
        // ── Wire 1: 首个 chunk → talking 动画 ──
        if (!firstChunkSent) {
          firstChunkSent = true;
          _sendOverlayCmd('playAnim', {'anim': 'talking'});
        }
        _sendChatChunk(fullText, requestId: requestId);
      },
      onDone: () {
        // ── Wire 1: 完成 → wave + 成功气泡 ──
        _sendOverlayCmd('playAnim', {'anim': 'wave'});
        _sendOverlayCmd('showBubble', {'text': '搞定啦~', 'durationMs': 3000});
        _sendChatDone(requestId: requestId);
      },
      onError: (msg) {
        // ── Wire 1: 出错 → failed + 错误气泡 ──
        _sendOverlayCmd('playAnim', {'anim': 'failed'});
        _sendOverlayCmd('showBubble', {'text': msg, 'durationMs': 4000});
        _sendChatError(msg, requestId: requestId);
      },
    );
  }
```

- [ ] **Step 3: 在类中添加 _sendOverlayCmd 私有方法**

在 `PetAgentCore` 类的 `_sendChatError` 方法之后（约第 530 行）添加：

```dart
  /// Wire 1+2: 向原生浮窗发送动画/气泡指令
  /// 通过 pet_overlay channel → PetForegroundService.handleCommand()
  void _sendOverlayCmd(String cmd, Map<String, dynamic> args) {
    try {
      _overlayChannel.invokeMethod('cmd', {
        'cmd': cmd,
        'args': args,
      });
    } catch (e) {
      PetLogger().error('Agent', '_sendOverlayCmd($cmd) failed', e);
    }
  }
```

- [ ] **Step 4: flutter analyze 验证**

```bash
cd c:/Users/lenovo/Desktop/ai-chat-app && /c/flutter/bin/flutter analyze lib/services/pet/pet_agent_core.dart
```

Expected: 0 issues.

- [ ] **Step 5: 提交**

```bash
git add lib/services/pet/pet_agent_core.dart
git commit -m "feat: Wire 1 — LLM stream phases mapped to native pet animations

- chatStream start → playAnim('run') + thinking bubble
- first chunk → playAnim('talking')
- done → playAnim('wave') + success bubble
- error → playAnim('failed') + error bubble
- New _sendOverlayCmd() sends via pet_overlay channel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Wire 2 — 状态机 → 原生动画

**Files:**
- Modify: `lib/services/pet/pet_overlay_host.dart:220-285`

**原理：** `PetOverlayController` 已有 `_controller`（PetController 实例）和 `_syncAnim()` 方法。只需在 `init()` 中订阅 `onStateChanged`，当 PetController 内部状态因衰减变化时自动同步到原生。

- [ ] **Step 1: 在 PetOverlayController 中添加状态同步回调**

修改 `lib/services/pet/pet_overlay_host.dart` 的 `init()` 方法，在 `_overlay.setMethodCallHandler(...)` 闭包之后、方法结束之前，添加状态订阅：

```dart
  void attachController(PetController controller) {
    _controller = controller;
    // ── Wire 2: 状态变更 → 原生动画 ──
    _controller!.onStateChanged = (state) {
      PetLogger().trace('Overlay', 'onStateChanged: status=${state.status.name}');
      _syncAnim();
    };
  }
```

- [ ] **Step 2: 增强 _syncAnim() 方法**

替换 `lib/services/pet/pet_overlay_host.dart` 的 `_syncAnim()` 方法（约第 320 行）为：

```dart
  /// Wire 2: 根据 Controller 当前状态同步原生动画 + 气泡
  void _syncAnim() {
    if (_controller == null) return;
    final s = _controller!.state;
    final status = s.status;

    switch (status) {
      case PetStatus.hungry:
        _cmd('playAnim', {'anim': 'hungry'});
        _showBubbleIfNeeded('好饿喵...🍖');
        break;
      case PetStatus.sleepy:
        _cmd('playAnim', {'anim': 'sleeping'});
        _showBubbleIfNeeded('好困...💤');
        break;
      case PetStatus.eating:
        _cmd('playAnim', {'anim': 'talking'});
        break;
      case PetStatus.happy:
        _cmd('playAnim', {'anim': 'wave'});
        break;
      case PetStatus.talking:
        _cmd('playAnim', {'anim': 'talking'});
        break;
      case PetStatus.sleeping:
        _cmd('playAnim', {'anim': 'sleeping'});
        break;
      case PetStatus.idle:
        _cmd('playAnim', {'anim': 'idle'});
        break;
    }
  }

  /// 防重复气泡：仅在当前无气泡时发送
  void _showBubbleIfNeeded(String text) {
    if (!_bubbleShowing) {
      _showBubbleWithDismiss(text);
    }
  }
```

- [ ] **Step 3: 在 main.dart 中调用 attachController**

修改 `lib/main.dart` 中 PetController 的 Provider 创建（约第 52 行），在 `PetController.shared = c` 之后添加：

```dart
      ChangeNotifierProvider(create: (_) { final c = PetController(); PetController.shared = c; petOverlayController.attachController(c); return c; }),
```

注意：需要在 `main.dart` 顶部添加 import：
```dart
import 'services/pet/pet_overlay_host.dart';
```

- [ ] **Step 4: flutter analyze 验证**

```bash
/c/flutter/bin/flutter analyze lib/services/pet/pet_overlay_host.dart lib/main.dart
```

Expected: 0 issues.

- [ ] **Step 5: 提交**

```bash
git add lib/services/pet/pet_overlay_host.dart lib/main.dart
git commit -m "feat: Wire 2 — state machine drives native pet animations

- PetOverlayController.attachController() subscribes to state changes
- _syncAnim() maps PetStatus → playAnim + contextual bubble
- _showBubbleIfNeeded() prevents duplicate bubbles
- main.dart calls attachController() on PetController init

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Wire 3 — 点宠物 → 迷你聊天

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/deepseek_chat/PetForegroundService.kt:155-165`

**原理：** `PetView.onTouchEvent("tap")` 回调已在 PetForegroundService 中处理。当前实现只转发给 Dart 层。需要改为：弹出原生 AlertDialog → 用户输入 → 通过 EngineBridge 发送到 Flutter Agent → 气泡显示回复。

- [ ] **Step 1: 修改 onTouchEvent 回调，tap 分支弹出 Dialog**

替换 `PetForegroundService.kt` 中 `showPetWindow()` 的 `onTouchEvent` 回调（约第 159 行）：

```kotlin
            // 触控回调
            onTouchEvent = { type, x, y ->
                Log.d("PetSvc", "touch: $type ($x, $y)")
                when (type) {
                    "tap" -> {
                        // ── Wire 3: 点击宠物 → 弹出迷你聊天 ──
                        showChatDialog()
                    }
                    else -> touchConsumer?.invoke(type, x, y)
                }
            }
```

- [ ] **Step 2: 在 PetForegroundService 类中添加 showChatDialog() 方法**

在 `PetForegroundService` 类中（约第 350 行之后，`handleCommand()` 附近）添加：

```kotlin
    /** Wire 3: 弹出迷你聊天对话框 */
    private fun showChatDialog() {
        val petView = this.petView ?: return
        val ctx = this@PetForegroundService

        // 创建输入框
        val input = android.widget.EditText(ctx).apply {
            hint = "想对糯糯说什么？"
            setSingleLine(false)
            maxLines = 3
            setPadding(32, 16, 32, 16)
            setTextColor(android.graphics.Color.BLACK)
        }

        val dialog = android.app.AlertDialog.Builder(ctx, android.R.style.Theme_DeviceDefault_Light_Dialog)
            .setTitle("和糯糯聊天")
            .setView(input)
            .setPositiveButton("发送") { _, _ ->
                val text = input.text.toString().trim()
                if (text.isNotEmpty()) {
                    // 通过 EngineBridge → Flutter PetAgentCore
                    EngineBridge.invokeMain("chatReq", mapOf(
                        "text" to text,
                        "requestId" to System.currentTimeMillis().toInt(),
                        "history" to emptyList<Map<String, Any>>()
                    ))
                    // 显示用户输入的气泡（即时反馈）
                    petView.showBubble(text, 2000)
                }
            }
            .setNegativeButton("取消", null)
            .create()

        // 使用 TYPE_APPLICATION_OVERLAY 弹出
        dialog.window?.setType(
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O)
                android.view.WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                android.view.WindowManager.LayoutParams.TYPE_PHONE
        )
        dialog.show()
    }
```

- [ ] **Step 3: flutter analyze + 构建验证**

```bash
/c/flutter/bin/flutter analyze
```

Expected: 0 issues (Kotlin 代码不在 Flutter analyze 范围，需通过 Android Studio 或 gradle 验证)。

- [ ] **Step 4: 提交**

```bash
git add android/app/src/main/kotlin/com/example/deepseek_chat/PetForegroundService.kt
git commit -m "feat: Wire 3 — tap pet opens native chat dialog

- onTouchEvent('tap') now triggers showChatDialog()
- AlertDialog with EditText for user input
- Sends text via EngineBridge.invokeMain('chatReq') → Flutter PetAgentCore
- Shows user's message as instant bubble feedback
- Uses TYPE_APPLICATION_OVERLAY for overlay-level dialog

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: 端到端验证

- [ ] **Step 1: 确认零残留错误**

```bash
cd c:/Users/lenovo/Desktop/ai-chat-app && /c/flutter/bin/flutter analyze
```

Expected: `No issues found!` (≤7 info 可接受)

- [ ] **Step 2: 构建 APK**

```bash
cd c:/Users/lenovo/Desktop/ai-chat-app/android && ./gradlew assembleDebug
```

Expected: BUILD SUCCESSFUL

- [ ] **Step 3: 提交 APK 构建产出**

```bash
git add -A
git commit -m "chore: finalize Agent wiring v1.1.0+2

Wire 1: LLM stream → native animations (run/talking/wave/failed)
Wire 2: State machine → native animations (hungry/sleepy/happy/etc)
Wire 3: Tap pet → native chat dialog → AI response

All 3 wires use existing MethodChannels, zero new dependencies.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## 验证清单

| # | 测试场景 | 预期行为 |
|---|---------|----------|
| 1 | 用户在 App 内发消息给 AI | 宠物显示 run → talking → wave |
| 2 | AI 返回错误 | 宠物显示 failed + 错误气泡 |
| 3 | 宠物饥饿值 <30（等待衰减） | 宠物切换 hungry 动画 + "好饿喵..." 气泡 |
| 4 | 宠物精力 <20 | 宠物切换 sleeping 动画 + "好困..." 气泡 |
| 5 | 点击桌面浮窗宠物 | 弹出"和糯糯聊天"对话框 |
| 6 | 在对话框中输入文字并发送 | 气泡即时显示用户输入，AI 回复通过动画+气泡呈现 |
| 7 | `flutter analyze` | 0 error, 0 warning |
