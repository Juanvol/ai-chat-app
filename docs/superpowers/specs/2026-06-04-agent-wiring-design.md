# Agent 集成 3 线接线 — 设计 Spec

> 版本 1.1.0 | 2026-06-04 | 状态：待评审

## 目标

将已实现的 Agent 核心（PetAgentCore / PetController / PetAiService）与 Android 原生浮窗层（PetForegroundService / PetView）通过 MethodChannel 接通，让弗糯糯从"贴图"升级为"有灵魂的 AI 伙伴"。

## 当前状态

| 模块 | 状态 | 说明 |
|------|------|------|
| PetAgentCore.chatStream() | ✅ 已实现 | 流式聊天，含 onChunk/onDone/onError 回调 |
| PetAgentCore.handleChatRequest() | ✅ 已实现 | 接收原生层聊天请求，通过 pet_agent_bridge 回传 |
| PetController (状态机) | ✅ 已实现 | hunger/mood/energy 衰减 + feed/play/pet/chat 交互 |
| PetController.onStateChanged | ✅ 已声明 | 回调字段存在，无订阅者 |
| PetOverlayController._overlay | ✅ 已实现 | MethodChannel `pet_overlay` 可发 playAnim/showBubble |
| PetForegroundService | ✅ 已实现 | 接收 pet_service / pet_overlay 两个 Channel |
| PetView.onTouchEvent | ✅ 已实现 | tap/doubleTap/drag/longPress 事件回调 |
| MiniChat | ✅ 已实现 | 迷你聊天 UI，通过 pet_agent_bridge 收发消息 |

## 3 根线

### 线 1：LLM 流 → 原生动画

**目标**：AI 处理状态实时反映到宠物动画。

| LLM 阶段 | 触发时机 | 原生动作 |
|----------|----------|----------|
| 开始处理 | chatStream() 调用时 | `playAnim("run")` + `showBubble("正在思考...")` |
| 流式输出中 | 首个 chunk 到达 | `playAnim("talking")` |
| 完成 | onDone 回调 | `playAnim("wave")` + `showBubble("搞定啦~")` |
| 出错 | onError 回调 | `playAnim("failed")` + `showBubble("信号不好喵...")` |

**改动点**：
- `lib/services/pet/pet_agent_core.dart` — `handleChatRequest()` 方法，在调用 `chatStream()` 前后插入 `_notifyNative()` 调用
- 新增私有方法 `_sendAnimToNative(anim, bubble)` → 通过 `pet_overlay` channel 发送

### 线 2：状态机 → 原生动画

**目标**：宠物内在状态（饥饿/困倦/开心）反映到原生层动画。

| Flutter 状态变更 | 触发时机 | 原生动作 |
|-----------------|----------|----------|
| PetStatus.eating | feed() 调用 | `playAnim("talking")` + eating 气泡 |
| PetStatus.happy | play()/pet() 调用 | `playAnim("wave")` + 开心气泡 |
| PetStatus.hungry | _decay() hunger<30 | `playAnim("hungry")` + 饥饿气泡 |
| PetStatus.sleepy | _decay() energy<20 | `playAnim("sleeping")` + 困倦气泡 |
| PetStatus.talking | chat() 调用 | `playAnim("talking")` |
| PetStatus.idle | 过渡计时器到期 | `playAnim("idle")` |

**改动点**：
- `lib/pet/pet_controller.dart` — `_notify()` 方法中追加 `_syncToNative()` 调用
- 新增私有方法 `_syncToNative()` → 根据当前 status 选择动画和气泡

### 线 3：点宠物 → 迷你聊天

**目标**：用户在桌面点击宠物 → 弹出输入框 → 发送到 AI → 气泡显示回复。

```
用户点击宠物 (PetView.onTouchEvent("tap"))
  → Kotlin 层: 显示 AlertDialog 输入框
  → 用户输入文本 → MethodChannel "pet_agent_bridge" invokeMethod("chatReq", {text, history})
  → Flutter 层: main.dart 接收 → PetAgentCore.handleChatRequest()
  → chatStream() 流式返回 → _sendChatChunk/_sendChatDone
  → Kotlin 层: 接收 chatChunk → 显示气泡（或走线 1 的动画流程）
```

**改动点**：
- `PetForegroundService.kt` — 在 `onTouchEvent("tap")` 回调中弹出 Dialog
- `PetView.kt` — 现有触碰事件已完备，无需改动
- `lib/services/pet/pet_agent_core.dart` — `handleChatRequest()` 已在 main.dart 中注册，无需额外改动

## 架构约束

- **不新增 MethodChannel**：复用现有 3 个 Channel（pet_service / pet_overlay / pet_agent_bridge）
- **不引入新依赖**
- **单引擎架构保持**：MethodChannel handler 统一在 main.dart 注册
- **Flutter→原生通信**：通过 `pet_overlay` channel 发送动画/气泡指令
- **原生→Flutter通信**：通过 `pet_agent_bridge` channel 发送聊天请求

## 版本号

当前 `1.0.0+1` → 目标 `1.1.0+2`（minor bump: 新功能，非 breaking change）

## 验证方式

1. `flutter analyze` — 0 error, 0 warning
2. 手动测试：发消息 → 宠物动画变化
3. 手动测试：饥饿值衰减到 <30 → 宠物显示 hungry
4. 手动测试：点击桌面宠物 → 弹出输入框 → 输入消息 → 气泡回复
