# MiniChat → Agent 通信桥设计

> **状态:** 设计完成，待实施
> **日期:** 2026-05-30
> **关联:** [2026-05-30-pet-agent-design.md](2026-05-30-pet-agent-design.md) — F7 引擎 #2 不直接调 LLM
> **依赖:** PetAgentCore (已完成), PetForegroundService (已完成), MiniChat (需改造)

---

## 目标

改造 MiniChat._send()，将 LLM 调用从引擎 #2（悬浮窗）迁移到引擎 #1（主 App），通过新建的 Kotlin 通信桥 + MethodChannel 实现跨引擎流式通信。零风险：旧路径完整保留，Feature Flag 默认走旧路径。

---

## 架构

### 新增组件

```
Android 进程
├── 引擎 #2 (petMain)                              ├── 引擎 #1 (main)
│   MiniChat                                        │   PetAgentCore
│     │ invokeMethod('chatReq')                     │     ▲ setMethodCallHandler
│     ▼                                             │     │
│   MethodChannel("pet_agent_bridge")               │   MethodChannel("pet_agent_bridge")
│     │                                             │     │
│     ▼                                             │     ▼
│   PetForegroundService.kt                         │   MainActivity.kt
│     │ EngineBridge.registerPetWindow()            │     │ EngineBridge.registerMain()
│     ▼                                             │     ▼
│   ┌────────────────── EngineBridge.kt ────────────┐
│   │  mainMessenger: BinaryMessenger?              │
│   │  petWindowMessenger: BinaryMessenger?         │
│   │  pendingQueue: List<PendingMessage>           │
│   │  invokeMain() / invokePetWindow()             │
│   └───────────────────────────────────────────────┘
└───────────────────────────────────────────────────
```

### Channel 职责分离

| Channel | 职责 | 持有者 |
|---------|------|--------|
| `pet_window` | UI 控制（窗口大小/位置/焦点/电池） | pet_window.dart |
| `pet_agent_bridge` (新) | Agent 通信（chatReq/chatChunk/chatDone/chatError） | mini_chat.dart + main.dart |

---

## 通信协议

### 引擎 #2 → 引擎 #1

| Method | Payload | 说明 |
|--------|---------|------|
| `chatReq` | `{text, history, requestId}` | MiniChat 发送用户消息 + 最近3轮上下文 |

### 引擎 #1 → 引擎 #2

| Method | Payload | 说明 |
|--------|---------|------|
| `chatChunk` | `{fullText, requestId}` | 流式 chunk（完整累计文本，防乱序） |
| `chatDone` | `{requestId}` | 流正常结束 |
| `chatError` | `{message, requestId}` | Agent 端错误 |

### 数据流（一次完整对话）

```
1. 用户输入 "你好"
2. MiniChat._sendViaAgent()
3. pet_agent_bridge.invokeMethod('chatReq', {text, history, requestId})
4. PetForegroundService → EngineBridge.invokeMain()
5. (如果 mainMessenger 为 null → pendingQueue)
6. MainActivity handler → PetAgentCore.handleChatRequest()
7. LLM Client.sendStream()
8. 每个 chunk (50ms 节流) → _sendChatChunk(fullText, requestId)
9. MainActivity → EngineBridge.invokePetWindow()
10. PetForegroundService → pet_agent_bridge.invokeMethod('chatChunk')
11. MiniChat handler → setState() 渲染
12. 流结束 → _sendChatDone()
13. MiniChat → isLoading = false
```

---

## 五层降级路径

```
用户发送消息
  │
  ├─ Feature Flag = false ─────────────────────► 走旧路径（100%现有行为）
  │
  └─ Feature Flag = true
       │
       ├─ EngineBridge.mainMessenger 为 null ───► pendingQueue 缓存，等 main 就绪
       │
       ├─ MethodChannel 调用异常 ──────────────► "糯糯在睡觉喵~ 打开App唤醒她 💤"
       │
       ├─ 30秒无响应（超时） ──────────────────► "...糯糯在想该怎么回你喵~"
       │
       ├─ 收到 chatError ──────────────────────► 显示 agent 返回的错误消息
       │
       └─ requestId 不匹配 ────────────────────► 静默忽略（已取消的旧请求）
```

---

## 文件变更清单

| 文件 | 操作 | 内容 |
|------|------|------|
| `android/.../EngineBridge.kt` | **新建** | 单例通信桥 + pendingQueue |
| `android/.../PetForegroundService.kt` | 修改 +2行 | registerPetWindow / clearPetWindow |
| `android/.../MainActivity.kt` | 修改 +20行 | pet_agent_bridge handler |
| `lib/services/pet_feature_flags.dart` | **新建** | Hive 持久化 boolean flag |
| `lib/pet/mini_chat.dart` | 修改 ~60行 | 分流 + _sendViaAgent + handler |
| `lib/services/pet_agent_core.dart` | 修改 +50行 | handleChatRequest + 流式推送 |
| `lib/main.dart` | 修改 +30行 | pet_agent_bridge handler + 懒初始化 Agent |
| 测试文件（3 个） | **新建/追加** | 见测试策略 |

---

## 关键设计决策

### 1. MiniChat 传上下文，Agent 不读 Hive
**原因:** 跨引擎 Hive 有同步延迟。MiniChat 本地已有完整 `_messages`，直接传最近 3 轮。

### 2. chatChunk 传完整累计文本，不传增量 index
**原因:** MethodChannel 不保证顺序。覆盖式渲染天然容忍乱序。

### 3. EngineBridge 用 object（Kotlin 单例），不传 Intent
**原因:** 同进程内存共享，不需要 Serializable/Parcelable。

### 4. Agent 懒初始化
**原因:** 收到第一条 chatReq 才 new PetAgentCore，避免 main.dart 启动时额外开销。

### 5. 50ms 节流 Agent 推送
**原因:** LLM ~20ms/token，不节流会导致高频 setState + invokeMethod，卡 UI。50ms 间隔 = ~20fps 更新，人眼感知流畅。

### 6. Feature Flag 用 Hive 存储
**原因:** 本地单用户 App，不需要 Firebase Remote Config / LaunchDarkly。Hive boolean 读写足够，defaultValue = false。

---

## 测试策略

### 新增测试（6+ 个）

| # | 文件 | 验证点 |
|---|------|--------|
| 1 | `test/pet/mini_chat_test.dart` | Feature Flag 关闭 → 走旧路径 |
| 2 | `test/pet/mini_chat_test.dart` | Feature Flag 开启 → 调 agentChatReq |
| 3 | `test/pet/mini_chat_test.dart` | 收到 chatChunk → 渲染累计文本 |
| 4 | `test/pet/mini_chat_test.dart` | 收到 chatDone → isLoading = false |
| 5 | `test/pet/mini_chat_test.dart` | chatError → 显示错误消息 |
| 6 | `test/pet/mini_chat_test.dart` | invokeMethod 异常 → 降级文案 |
| 7 | `test/services/pet_agent_core_test.dart` | handleChatRequest → 发送 chatChunk |
| 8 | `test/services/pet_agent_core_test.dart` | requestId 取消 → 忽略旧 chunk |

### 回归约束
现有基础 252 测试 + MiniChat 现有 9 测试必须全部通过。

---

## 实施顺序

1. EngineBridge.kt（纯新增，零风险）
2. pet_feature_flags.dart（纯新增）
3. MainActivity.kt + PetForegroundService.kt（新增 handler + 注册，不改现有方法）
4. main.dart agent handler（新增 handler + 懒初始化）
5. pet_agent_core.dart handleChatRequest（新增方法，不改现有方法）
6. mini_chat.dart 改造（分流 + _sendViaAgent）
7. 测试 → 验证 → 提交
