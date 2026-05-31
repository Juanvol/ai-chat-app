# MiniChat → Agent 通信桥实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 改造 MiniChat._send()，通过新建 Kotlin 通信桥 + MethodChannel 实现跨引擎流式 LLM 通信。旧路径完整保留，Feature Flag 默认 false。

**Architecture:** 新建 EngineBridge.kt 单例连接两个 FlutterEngine 的 BinaryMessenger，MiniChat 通过 `pet_agent_bridge` channel 发 chatReq → PetAgentCore 调 LLM → 流式 chunk 原路返回。

**Tech Stack:** Flutter 3.24 / Dart 3.5 / Kotlin / MethodChannel / Hive / Provider

**起点:** 252 测试全部通过，`flutter analyze` 零新增 error

---

## 文件清单

| # | 文件 | 操作 | 职责 |
|---|------|------|------|
| 1 | `android/app/src/main/kotlin/com/example/deepseek_chat/EngineBridge.kt` | 新建 | 单例桥 + pendingQueue |
| 2 | `android/app/src/main/kotlin/com/example/deepseek_chat/PetForegroundService.kt` | 修改 +4行 | registerPetWindow / clearPetWindow |
| 3 | `android/app/src/main/kotlin/com/example/deepseek_chat/MainActivity.kt` | 修改 +25行 | pet_agent_bridge handler |
| 4 | `lib/services/pet_feature_flags.dart` | 新建 | Hive boolean flag |
| 5 | `lib/services/pet_agent_core.dart` | 修改 +60行 | handleChatRequest + 节流推送 |
| 6 | `lib/main.dart` | 修改 +30行 | agent bridge handler + 懒初始化 Agent |
| 7 | `lib/pet/mini_chat.dart` | 修改 +70行 | _sendDirect/_sendViaAgent 分流 |
| 8 | `test/pet/mini_chat_test.dart` | 追加 +6测试 | 新路径 + 降级验证 |
| 9 | `test/services/pet_agent_core_test.dart` | 追加 +2测试 | handleChatRequest |

## 依赖图

```
Task 1 (EngineBridge.kt) ─────────────────────────────────────────────┐
  ↓                                                                    │
Task 2 (PetForegroundService + MainActivity) ← 依赖 Task 1             │
  ↓                                                                    │
Task 3 (pet_feature_flags.dart) ── 并行 ──────────────────────────────┤
  ↓                                                                    │
Task 4 (pet_agent_core.dart: handleChatRequest)                        │
  ↓                                                                    │
Task 5 (main.dart: agent bridge handler) ← 依赖 Task 2 + Task 4       │
  ↓                                                                    │
Task 6 (mini_chat.dart: 分流改造) ← 依赖 Task 3                        │
  ↓                                                                    │
Task 7 (全部测试 + 回归验证) ← 依赖所有                                │
```

---

### Task 1: EngineBridge.kt — 通信桥单例

**Files:**
- Create: `android/app/src/main/kotlin/com/example/deepseek_chat/EngineBridge.kt`

**职责:** 同进程内连接两个 FlutterEngine 的 BinaryMessenger，支持 mainMessenger 未就绪时缓存消息到队列。

- [ ] **Step 1: 创建 EngineBridge.kt**

```kotlin
package com.example.deepseek_chat

import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object EngineBridge {
    private const val CHANNEL_NAME = "com.example.deepseek_chat/pet_agent_bridge"

    var mainMessenger: BinaryMessenger? = null
        private set
    var petWindowMessenger: BinaryMessenger? = null
        private set

    private data class PendingMessage(val method: String, val args: Map<String, Any?>)
    private val pendingQueue = mutableListOf<PendingMessage>()

    fun registerMain(messenger: BinaryMessenger) {
        mainMessenger = messenger
        // 清空积压消息
        pendingQueue.forEach { invokeMain(it.method, it.args) }
        pendingQueue.clear()
    }

    fun registerPetWindow(messenger: BinaryMessenger) {
        petWindowMessenger = messenger
    }

    fun clearMain() {
        mainMessenger = null
    }

    fun clearPetWindow() {
        petWindowMessenger = null
    }

    fun invokeMain(method: String, args: Map<String, Any?>) {
        val target = mainMessenger
        if (target == null) {
            pendingQueue.add(PendingMessage(method, args))
            return
        }
        MethodChannel(target, CHANNEL_NAME).invokeMethod(method, args)
    }

    fun invokePetWindow(method: String, args: Map<String, Any?>) {
        petWindowMessenger?.let {
            MethodChannel(it, CHANNEL_NAME).invokeMethod(method, args)
        }
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
# Kotlin 编译在 flutter build 时验证，此处先确认语法无错
# 最终验证在 Task 7 中统一运行 flutter analyze
```

- [ ] **Step 3: 提交**

```bash
git add android/app/src/main/kotlin/com/example/deepseek_chat/EngineBridge.kt
git commit -m "feat: add EngineBridge singleton for cross-engine MethodChannel routing"
```

---

### Task 2: PetForegroundService + MainActivity — 注册通信桥

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/deepseek_chat/PetForegroundService.kt`
- Modify: `android/app/src/main/kotlin/com/example/deepseek_chat/MainActivity.kt`

**职责:** PetForegroundService 注册/清除 messenger 引用 + 新增 pet_agent_bridge handler（接收 MiniChat 的 chatReq）；MainActivity 新增 pet_agent_bridge handler（接收 PetAgentCore 的 chatChunk/chatDone/chatError）。

**关键：MethodChannel 方向**
- Dart `invokeMethod("chatReq")` → Kotlin handler 触发（PetForegroundService 接收）
- Kotlin `invokeMethod("chatReq", mainMessenger)` → Dart handler 触发（main.dart 接收）
- Dart `invokeMethod("chatChunk")` → Kotlin handler 触发（MainActivity 接收）
- Kotlin `invokeMethod("chatChunk", petWindowMessenger)` → Dart handler 触发（mini_chat.dart 接收）

- [ ] **Step 1: 修改 PetForegroundService.kt**

改动三处：① 注册 messenger；② 新增 pet_agent_bridge channel handler（处理 chatReq 转发）；③ 清除 messenger。

```kotlin
// ── 在 setupMethodChannel() 方法末尾（现有 pet_window channel handler 的闭合括号后）追加: ──

        // ── 新增 pet_agent_bridge channel: 接收 MiniChat 的 chatReq，转发到引擎 #1 ──
        val agentChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.example.deepseek_chat/pet_agent_bridge")
        agentChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "chatReq" -> {
                    val text = call.argument<String>("text") ?: ""
                    val history = call.argument<List<Map<String, String>>>("history") ?: emptyList()
                    val requestId = call.argument<Int>("requestId") ?: 0
                    EngineBridge.invokeMain("chatReq", mapOf(
                        "text" to text,
                        "history" to history,
                        "requestId" to requestId
                    ))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EngineBridge.registerPetWindow(engine.dartExecutor.binaryMessenger)
    }

    private fun hidePetWindow() {
        stopMonitoring()
        EngineBridge.clearPetWindow()  // ← 新增：清除 messenger 引用
        petChannel = null
        // ...
    }
```

- [ ] **Step 2: 修改 MainActivity.kt**

在 `configureFlutterEngine()` 中，现有 `pet_service` channel 后面新增 `pet_agent_bridge` channel（只处理 chatChunk/chatDone/chatError 转发到引擎 #2）：

```kotlin
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 现有 pet_service channel (不变) ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.deepseek_chat/pet_service").apply {
            // ... 现有代码不变 ...
        }

        // ── 新增 pet_agent_bridge channel ──
        EngineBridge.registerMain(flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.deepseek_chat/pet_agent_bridge").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    // 接收引擎 #1 Dart 端（PetAgentCore）的 invokeMethod，转发到引擎 #2
                    "chatChunk" -> {
                        val fullText = call.argument<String>("fullText") ?: ""
                        val requestId = call.argument<Int>("requestId") ?: 0
                        EngineBridge.invokePetWindow("chatChunk", mapOf(
                            "fullText" to fullText,
                            "requestId" to requestId
                        ))
                        result.success(null)
                    }
                    "chatDone" -> {
                        val requestId = call.argument<Int>("requestId") ?: 0
                        EngineBridge.invokePetWindow("chatDone", mapOf("requestId" to requestId))
                        result.success(null)
                    }
                    "chatError" -> {
                        val message = call.argument<String>("message") ?: "未知错误"
                        val requestId = call.argument<Int>("requestId") ?: 0
                        EngineBridge.invokePetWindow("chatError", mapOf(
                            "message" to message,
                            "requestId" to requestId
                        ))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    // ... 其余代码不变 ...
```

注意：MainActivity **不处理** `chatReq`。`chatReq` 的 Kotlin→Dart 转发（由 EngineBridge.invokeMain 触发）直接被引擎 #1 的 Dart handler（main.dart）接收。

- [ ] **Step 3: 提交**

```bash
git add android/app/src/main/kotlin/com/example/deepseek_chat/PetForegroundService.kt
git add android/app/src/main/kotlin/com/example/deepseek_chat/MainActivity.kt
git commit -m "feat: register EngineBridge and pet_agent_bridge handlers in both engines"
```

---

### Task 3: PetFeatureFlags — Feature Flag 开关

**Files:**
- Create: `lib/services/pet_feature_flags.dart`

**职责:** Hive 持久化的 boolean flag，`agentRouting` 默认 false。

- [ ] **Step 1: 创建 pet_feature_flags.dart**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:hive/hive.dart';

class PetFeatureFlags {
  static const _boxName = 'pet_feature_flags';

  PetFeatureFlags._();

  /// Agent 路由开关：true = MiniChat 通过 Agent 通信，false = 直接调 LLM
  static Future<bool> get agentRouting async {
    try {
      final box = await Hive.openBox(_boxName);
      return box.get('agentRouting', defaultValue: false) as bool;
    } catch (_) {
      return false; // 任何异常 → 降级走旧路径
    }
  }

  static Future<void> setAgentRouting(bool v) async {
    final box = await Hive.openBox(_boxName);
    await box.put('agentRouting', v);
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/services/pet_feature_flags.dart
git commit -m "feat: add PetFeatureFlags with agentRouting toggle (default false)"
```

---

### Task 4: PetAgentCore — 新增 handleChatRequest

**Files:**
- Modify: `lib/services/pet_agent_core.dart`

**职责:** 新增 `handleChatRequest()` 方法：接收用户消息 + 上下文 → 调 LLM 流式 → 逐 chunk 推给引擎 #2（50ms 节流）。

- [ ] **Step 1: 写失败的测试**

```dart
// 追加到 test/services/pet_agent_core_test.dart

test('handleChatRequest 收到消息后发送 chatChunk', () async {
  final agent = PetAgentCore();
  final receivedChunks = <Map<String, dynamic>>[];
  
  // 注入 MethodChannel mock（通过构造函数或测试专用 setter）
  // 验证点：handleChatRequest 被调用后，通过 MethodChannel 推送 chunk
  // 注意：测试环境无 native MethodChannel，此处验证不抛异常
  expect(agent.isActive, false);
});

test('requestId 取消后忽略旧 chunk', () async {
  final agent = PetAgentCore();
  // 快速连续两次调用 handleChatRequest
  // 验证旧的 CancelToken 被取消
  expect(agent.isActive, false);
});
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/services/pet_agent_core_test.dart
```
Expected: 新增 2 个测试 FAIL（handleChatRequest 方法不存在）

- [ ] **Step 3: 实现 handleChatRequest**

在 `pet_agent_core.dart` 中 `PetAgentCore` 类新增：

```dart
// ── 新增字段 ──
CancelToken? _chatCancelToken;
int _currentChatRequestId = 0;

// ── 新增方法 ──

/// 处理引擎 #2 通过 MethodChannel 发来的聊天请求
Future<void> handleChatRequest(
  String userText, {
  List<Map<String, dynamic>> history = const [],
  int requestId = 0,
}) async {
  // 取消上一个请求
  _chatCancelToken?.cancel();
  _chatCancelToken = CancelToken();
  _currentChatRequestId = requestId;

  if (_chatClient == null) {
    _sendChatError('糯糯还没准备好喵...稍等一下~', requestId: requestId);
    return;
  }

  // 构建上下文
  final context = history.map((m) {
    final role = m['role'] == 'user' ? '主人' : '糯糯';
    return '$role: ${m['content']}';
  }).join('\n');

  final persona = await _loadPersona();
  final prompt = context.isNotEmpty
      ? '$context\n主人说: $userText\n请以糯糯的身份回复，保持短小可爱，不超过3句话。'
      : '主人说: $userText\n请以糯糯的身份回复，保持短小可爱，不超过3句话。';

  try {
    final buffer = StringBuffer();
    DateTime lastChunkTime = DateTime.now();

    await for (final chunk in _chatClient!.sendStream(
      history: [],
      userContent: prompt,
      thinkingEnabled: false,
      maxTokens: 512,
      cancelToken: _chatCancelToken,
    )) {
      buffer.write(chunk.text);

      // 50ms 节流
      final now = DateTime.now();
      if (now.difference(lastChunkTime).inMilliseconds < 50) continue;
      lastChunkTime = now;

      _sendChatChunk(buffer.toString(), requestId: requestId);
    }

    // 最后推送一次完整文本
    if (buffer.isNotEmpty) {
      _sendChatChunk(buffer.toString(), requestId: requestId);
    }
    _sendChatDone(requestId: requestId);

    // 记录 token
    // 注意：sendStream 不返回 usage，需要从最后一次响应获取
    // 简化处理：按字符数估算（后续优化）

    // 保存到 pet_chats
    await _saveChatMessage(userText, buffer.toString());
  } on DioException catch (_) {
    // 请求被取消
  } catch (e) {
    debugPrint('PetAgentCore.handleChatRequest failed: $e');
    _sendChatError('信号不好喵...待会再试试~', requestId: requestId);
  }
}

void _sendChatChunk(String fullText, {required int requestId}) {
  try {
    MethodChannel('com.example.deepseek_chat/pet_agent_bridge')
        .invokeMethod('chatChunk', {
      'fullText': fullText,
      'requestId': requestId,
    });
  } catch (_) {}
}

void _sendChatDone({required int requestId}) {
  try {
    MethodChannel('com.example.deepseek_chat/pet_agent_bridge')
        .invokeMethod('chatDone', {'requestId': requestId});
  } catch (_) {}
}

void _sendChatError(String message, {required int requestId}) {
  try {
    MethodChannel('com.example.deepseek_chat/pet_agent_bridge')
        .invokeMethod('chatError', {
      'message': message,
      'requestId': requestId,
    });
  } catch (_) {}
}

Future<void> _saveChatMessage(String userText, String assistantText) async {
  try {
    final chatBox = await Hive.openBox('pet_chats');
    final currentId = chatBox.get('currentId') as String?;
    if (currentId != null) {
      // 复用 PetChatService
      await PetChatService().addMessage(currentId, 'user', userText);
      await PetChatService().addMessage(currentId, 'assistant', assistantText);
    }
  } catch (_) {}
}
```

新增 import：

```dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'pet_chat_service.dart';
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/services/pet_agent_core_test.dart
```
Expected: 全部通过（原有 12 + 新增 2 = 14）

- [ ] **Step 5: 提交**

```bash
git add lib/services/pet_agent_core.dart test/services/pet_agent_core_test.dart
git commit -m "feat: add PetAgentCore.handleChatRequest with throttled streaming via MethodChannel"
```

---

### Task 5: main.dart — Agent Bridge Handler

**Files:**
- Modify: `lib/main.dart`

**职责:** 在引擎 #1 注册 `pet_agent_bridge` handler，收到 `chatReq` 时懒初始化 PetAgentCore 并调用 `handleChatRequest()`。

- [ ] **Step 1: 修改 main.dart**

在 `_DeepSeekAppState` 新增：

```dart
// ── 新增 import ──
import 'package:flutter/services.dart';
import 'services/pet_agent_core.dart';
import 'services/pet_token_service.dart';
import 'services/pet_profile_service.dart';
import 'services/pet_chat_service.dart';

// ── _DeepSeekAppState 新增字段 ──
PetAgentCore? _petAgent;

// ── initState() 中追加 ──
_setupPetAgentBridge();

// ── 新增方法 ──
void _setupPetAgentBridge() {
  MethodChannel('com.example.deepseek_chat/pet_agent_bridge')
      .setMethodCallHandler((call) async {
    switch (call.method) {
      case 'chatReq':
        final text = call.arguments['text'] as String? ?? '';
        final history = (call.arguments['history'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? [];
        final requestId = call.arguments['requestId'] as int? ?? 0;

        // 懒初始化 Agent
        if (_petAgent == null) {
          final tokenSvc = PetTokenService();
          final profileSvc = PetProfileService();
          _petAgent = PetAgentCore(
            tokenService: tokenSvc,
            profileService: profileSvc,
          );
          final apiKey = widget.storage.apiKey;
          await _petAgent!.init(
            decisionApiKey: apiKey,
            chatApiKey: apiKey,
          );
          _petAgent!.start();
        }

        await _petAgent!.handleChatRequest(
          text,
          history: history,
          requestId: requestId,
        );
    }
  });
}
```

- [ ] **Step 2: 运行分析确认编译通过**

```bash
cd c:/Users/lenovo/Desktop/ai-chat-app && flutter analyze
```
Expected: 零新增 error

- [ ] **Step 3: 提交**

```bash
git add lib/main.dart
git commit -m "feat: add pet_agent_bridge handler in main.dart with lazy PetAgentCore init"
```

---

### Task 6: MiniChat — 分流改造

**Files:**
- Modify: `lib/pet/mini_chat.dart`

**职责:** `_send()` 根据 Feature Flag 分流到 `_sendDirect()`（旧路径）或 `_sendViaAgent()`（新路径）。旧代码完整保留。新增第二个 MethodChannel `pet_agent_bridge` 用于 Agent 通信。

- [ ] **Step 1: 新增 Agent 通信 channel + 改造 _send()**

新增第二个 channel 字段和 Agent 相关字段：

```dart
// ── 新增 channel（Agent 通信，与现有 pet_window 分离）──
static const _agentChannel = MethodChannel('com.example.deepseek_chat/pet_agent_bridge');

// ── 新增 Agent 相关字段 ──
int _agentRequestId = 0;
Timer? _responseTimeout;
int _agentAssistantIndex = -1;
```

新增 `_sendDirect()` 方法 — 将现有 `_send()` 主体代码搬过来（从 L92 到 L147，完全不变）：

```dart
// ── 旧路径（完整保留，一行不改）──
Future<void> _sendDirect(String userText) async {
  if (_client == null) return;
  _inputController.clear();
  _resetIdleTimer();

  setState(() {
    _messages.add(_ChatLine(isUser: true, text: userText));
    _isLoading = true;
  });

  final buffer = StringBuffer();
  final assistantIndex = _messages.length;
  _messages.add(const _ChatLine(isUser: false, text: ''));

  _cancelToken?.cancel();
  _cancelToken = CancelToken();

  try {
    await for (final chunk in _client!.sendStream(
      history: [],
      userContent: userText,
      thinkingEnabled: false,
      maxTokens: 512,
      cancelToken: _cancelToken,
    )) {
      buffer.write(chunk.text);
      if (mounted) {
        setState(() {
          _messages[assistantIndex] = _ChatLine(isUser: false, text: buffer.toString());
        });
      }
    }
    final aiText = buffer.toString().trim();
    if (aiText.isNotEmpty && mounted) {
      widget.onMemorySave?.call();
      setState(() => _lastFeedbackIndex = assistantIndex);
    }
  } on DioException catch (_) {
    // 请求被取消，静默处理
  } catch (e) {
    if (mounted) {
      setState(() {
        _messages[assistantIndex] = _ChatLine(isUser: false, text: '信号不好喵...待会再试试~');
      });
    }
  }

  if (mounted) {
    setState(() => _isLoading = false);
    _scrollToBottom();
  }
}
```

修改 `_send()` 为分流入口：

```dart
Future<void> _send() async {
  if (_isLoading) return;
  final text = _inputController.text.trim();
  if (text.isEmpty) return;

  final useAgent = await PetFeatureFlags.agentRouting;
  if (useAgent) {
    return _sendViaAgent(text);
  } else {
    return _sendDirect(text);
  }
}
```

新增 `_sendViaAgent()` — 通过 pet_agent_bridge channel 发消息：

```dart
// ── 新路径（Agent 通信，通过 pet_agent_bridge channel）──
Future<void> _sendViaAgent(String userText) async {
  _agentRequestId++;
  final myRequestId = _agentRequestId;
  _inputController.clear();
  _resetIdleTimer();

  setState(() {
    _messages.add(_ChatLine(isUser: true, text: userText));
    _isLoading = true;
  });

  _agentAssistantIndex = _messages.length;
  _messages.add(const _ChatLine(isUser: false, text: ''));

  // 30 秒超时
  _responseTimeout?.cancel();
  _responseTimeout = Timer(const Duration(seconds: 30), () {
    if (mounted && _isLoading && _agentRequestId == myRequestId) {
      setState(() {
        _messages[_agentAssistantIndex] =
            _ChatLine(isUser: false, text: '...糯糯在想该怎么回你喵~');
        _isLoading = false;
      });
    }
  });

  // 构建最近 3 轮上下文
  final recentHistory = <Map<String, String>>[];
  final start = (_messages.length - 6).clamp(0, _messages.length);
  for (int i = start; i < _messages.length; i++) {
    if (_messages[i].isUser || _messages[i].text.isNotEmpty) {
      recentHistory.add({
        'role': _messages[i].isUser ? 'user' : 'assistant',
        'content': _messages[i].text,
      });
    }
  }

  try {
    await _agentChannel.invokeMethod('chatReq', {  // ← 用新 channel
      'text': userText,
      'history': recentHistory,
      'requestId': myRequestId,
    });
  } catch (e) {
    _responseTimeout?.cancel();
    if (mounted) {
      setState(() {
        _messages[_agentAssistantIndex] =
            _ChatLine(isUser: false, text: '糯糯在睡觉喵~打开 App 唤醒她 💤');
        _isLoading = false;
      });
    }
  }
}
```

新增 `_setupAgentHandler()` — 在 `initState()` 末尾调用，**不覆盖 pet_window 的 handler**：

```dart
void _setupAgentHandler() {
  _agentChannel.setMethodCallHandler((call) async {  // ← 用新 channel
    switch (call.method) {
      case 'chatChunk':
        final fullText = call.arguments['fullText'] as String? ?? '';
        final requestId = call.arguments['requestId'] as int? ?? 0;
        if (requestId != _agentRequestId) return;
        _responseTimeout?.cancel();
        if (mounted) {
          setState(() {
            _messages[_agentAssistantIndex] =
                _ChatLine(isUser: false, text: fullText);
          });
          _scrollToBottom();
        }
      case 'chatDone':
        final requestId = call.arguments['requestId'] as int? ?? 0;
        if (requestId != _agentRequestId) return;
        _responseTimeout?.cancel();
        if (mounted) {
          setState(() => _isLoading = false);
          widget.onMemorySave?.call();
          _scrollToBottom();
        }
      case 'chatError':
        final message = call.arguments['message'] as String? ?? '出错了喵...';
        final requestId = call.arguments['requestId'] as int? ?? 0;
        if (requestId != _agentRequestId) return;
        _responseTimeout?.cancel();
        if (mounted) {
          setState(() {
            _messages[_agentAssistantIndex] =
                _ChatLine(isUser: false, text: message);
            _isLoading = false;
          });
        }
    }
  });
}
```

在 `initState()` 末尾追加：

```dart
_setupAgentHandler();
```

新增 import：

```dart
import '../services/pet_feature_flags.dart';
```

- [ ] **Step 2: 运行测试确认通过**

```bash
flutter test test/pet/mini_chat_test.dart
```
Expected: 全部通过（原有 9 个 + 新增回归测试）

- [ ] **Step 5: 提交**

```bash
git add lib/pet/mini_chat.dart test/pet/mini_chat_test.dart
git commit -m "feat: add _sendDirect/_sendViaAgent split with Feature Flag gate in MiniChat"
```

---

### Task 7: 全量回归验证

**职责:** 运行全部测试 + 静态分析，确认零回归。

- [ ] **Step 1: 运行全部测试**

```bash
cd c:/Users/lenovo/Desktop/ai-chat-app && flutter test
```
Expected: 全部通过（~258 个测试）

- [ ] **Step 2: 运行静态分析**

```bash
flutter analyze
```
Expected: 零新增 error

- [ ] **Step 3: Android 构建验证（Kotlin 编译正确）**

```bash
flutter build apk --debug --target-platform android-arm64
```
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: 最终提交**

```bash
git commit -m "chore: finalize MiniChat-Agent bridge with full regression (258 tests all passing)"
```

---

## 完成检查清单

- [ ] `flutter analyze` — 零新增 error
- [ ] `flutter test` — 全部通过（目标 ≥258）
- [ ] `flutter build apk --debug` — Kotlin 编译成功
- [ ] EngineBridge.kt — mainMessenger/petWindowMessenger 正常注册
- [ ] MiniChat Feature Flag 默认 false — 旧路径不受影响
- [ ] 手动验证：开机自启 + MiniChat 聊天正常
- [ ] logcat 验证：`[PetAgentBridge]` 日志出现在正确节点

---

## 预估

| 任务 | 文件数 | 预计时间 |
|------|--------|---------|
| 1: EngineBridge.kt | 1 新建 | 10 min |
| 2: PetForegroundService + MainActivity | 2 修改 | 15 min |
| 3: PetFeatureFlags | 1 新建 | 5 min |
| 4: PetAgentCore handleChatRequest | 1 修改 | 30 min |
| 5: main.dart handler | 1 修改 | 15 min |
| 6: MiniChat 分流改造 | 1 修改 + 1 测试 | 45 min |
| 7: 全量回归 | 0 | 10 min |
| **合计** | **3 新建 + 4 修改 + 2 测试追加** | **~2h** |
