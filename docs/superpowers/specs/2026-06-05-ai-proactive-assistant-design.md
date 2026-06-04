# AI 主动建议 + 智能助理 — 设计 Spec

> 2026-06-05 | D8 · Phase 2 养成深化

## 一、目标

把弗糯糯从「会说话的电子宠物」升级为「有个性的 AI 桌面助理」。

**核心差异：**

| | 现有（v1.1） | 目标（v1.2） |
|---|---|---|
| 说话时机 | 定时器随机 | 场景感知 + 事件驱动 |
| 说话内容 | 1-2 句卖萌气泡 | 分层建议：闲聊→场景→深度意见 |
| 记忆 | 无长期记忆 | 用户画像 + 兴趣标签 + 情景归档 |
| 日记 | 手动事件记录 | AI 自动生成 + 每日总结 |
| 主动性 | 被动响应 | 主动提醒/关心/给意见 |
| Token 意识 | 无 | 预算感知调度 + 模型降级 |

---

## 二、系统架构

```
┌──────────────────────────────────────────────────────────┐
│                   SuggestionEngine                        │
│                                                          │
│  ┌─────────────────┐   ┌───────────────────────────┐    │
│  │  TriggerManager  │   │     ContextCollector       │    │
│  │                  │   │                            │    │
│  │ · Timer Scheduler│   │ · 最近对话 (Hive)          │    │
│  │ · Screen Watcher │   │ · 宠物记忆 (pet_memories)  │    │
│  │ · Event Listener │   │ · 日记摘要 (pet_diary)      │    │
│  │ · Time Awareness │   │ · 用户画像 (pet_profile)   │    │
│  │ · Idle Wakeup    │   │ · 当前屏幕 (vision)        │    │
│  └────────┬─────────┘   └───────────┬───────────────┘    │
│           │                         │                     │
│           ▼                         ▼                     │
│  ┌──────────────────────────────────────────────────┐    │
│  │            Budget Gate (Token 预算感知)            │    │
│  │  剩余 > 20k → 全功能   │  > 5k → 仅文本   │  < 5k → 仅规则    │
│  └──────────────────────┬───────────────────────────┘    │
│                         │                                 │
│                         ▼                                 │
│  ┌──────────────────────────────────────────────────┐    │
│  │          Decision LLM (复用 PetAgentCore)          │    │
│  │  "该不该说话？层级？话题方向？"  max 64 tokens       │    │
│  └──────────┬──────────────────┬────────────────────┘    │
│             │                  │                          │
│     L1-L2  │                  │  L3-L4                   │
│            ▼                  ▼                          │
│  ┌──────────────────┐  ┌──────────────────────┐         │
│  │  Bubble Output    │  │  Chat Output          │         │
│  │  · 气泡 + 点击进聊天│  │  · 直接弹迷你聊天      │         │
│  │  · 左滑忽略(学习)  │  │  · 或通知栏提醒        │         │
│  │  · 自动记入日记    │  │  · 自动归档记忆        │         │
│  └──────────────────┘  └──────────────────────┘         │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │          ContextCollector (输入通道)                │    │
│  │  ┌──────────┬──────────┬──────────┬──────────┐   │    │
│  │  │ 对话历史  │ 宠物记忆  │ 宠物日记  │ 用户画像  │   │    │
│  │  │ (always)  │ (always)  │ (always)  │ (always)  │   │    │
│  │  ├──────────┼──────────┼──────────┼──────────┤   │    │
│  │  │ 屏幕截图  │ App统计   │ 剪贴板    │ MCP 工具  │   │    │
│  │  │ (vision)  │ (future)  │ (future)  │ (future)  │   │    │
│  │  └──────────┴──────────┴──────────┴──────────┘   │    │
│  └──────────────────────────────────────────────────┘    │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │              UX Layer (用户感知)                    │    │
│  │  · 透明度标注 (为什么说这句话)                      │    │
│  │  · 建议历史 (可回溯)                               │    │
│  │  · 反馈学习 (左滑忽略→降权 / 点击→升权)            │    │
│  │  · 打扰熔断 (1h > 3次 → 静默 2h)                  │    │
│  │  · 隐私信号 (截图时 👁 图标)                       │    │
│  │  · 渐进解锁 (Day 1→L1, Day 3→L2, Day 7→L4...)   │    │
│  └──────────────────────────────────────────────────┘    │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │            Token Dashboard (用户可见)              │    │
│  │  · 日预算滑块 (5k/15k/50k 三档 + 自定义)          │    │
│  │  · 功能开关 (可单独关 Vision/深度建议/日记)       │    │
│  │  · 实时用量仪表盘 (今日/本周/本月)                 │    │
│  │  · 超预算保护 (用尽 → 💤 仅响应主动聊天)          │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

### 与现有系统的复用

| 现有组件 | 复用方式 |
|---------|---------|
| `PetAgentCore` | Decision LLM 复用其 3 层 token 过滤架构 |
| `PetTokenService` | 预算门控 + 消费记录 |
| `PetDiaryService` | L2+ 建议自动写日记条目 |
| `PetMemory` (Hive) | 扩展为长期情景记忆 |
| `PetPersona` | 角色模式 = 切换 system prompt |
| `PetForegroundService` (Kotlin) | 气泡→聊天联动已支持 |

---

## 二-B、大厂级架构规范

### 核心原则：一切可变的就是插件

```
                        ┌───────────────────┐
                        │  SuggestionEngine  │  ← 纯协调器，不动业务逻辑
                        │  (core orchestrator)│
                        └───────┬───────────┘
                                │
            ┌───────────────────┼───────────────────┐
            │                   │                   │
    ┌───────▼───────┐  ┌───────▼───────┐  ┌───────▼───────┐
    │ IInputSource   │  │ IDecisionPipe │  │ IOutputDriver  │
    │ (输入插件)      │  │ (决策管道)     │  │ (输出插件)      │
    └───────┬───────┘  └───────────────┘  └───────┬───────┘
    ┌───────┼───────┐                           ┌───────┼───────┐
    │       │       │                           │       │       │
  Timer  Vision  Voice                         Bubble  Chat  Notif
  Source Source  Source                        Driver  Driver Driver
  (now)  (now)  (future)                       (now)  (now)  (future)
```

任何一个功能新增 = 实现一个接口 + 注册到引擎。不改核心代码。

### 接口定义

```dart
// ── 输入插件 ──

/// 输入源接口：任何能给糯糯提供上下文的东西都实现这个
abstract class IInputSource {
  /// 唯一标识，用于日志/开关/预算计量
  String get id;

  /// 优先级 0-100（高优先级的上下文会被优先消费）
  int get priority;

  /// 是否已启用（受预算/用户设置控制）
  bool get isEnabled;

  /// Token 消耗等级：none | cheap | normal | expensive
  TokenCostLevel get costLevel;

  /// 采集上下文，返回 null 表示本轮无新信息
  /// 异步但必须可超时取消（5s timeout）
  Future<InputSnapshot?> collect({required DateTime since});

  /// 释放资源（如关闭截图流、断开 MCP 连接）
  void dispose();
}

/// 一次采集的快照
class InputSnapshot {
  final String sourceId;
  final String summary;       // 供 LLM 阅读的摘要（< 200 字符）
  final Map<String, dynamic>? metadata;  // 结构化附加数据
  final DateTime collectedAt;
}

// ── 输出插件 ──

/// 输出驱动接口：气泡/聊天/通知/语音都实现这个
abstract class IOutputDriver {
  String get id;

  /// 按照层级选择输出方式
  /// L1 → bubble, L2 → bubble(clickable), L3-L4 → chat dialog
  bool canHandle(SuggestionLevel level);

  /// 执行输出
  Future<void> deliver(Suggestion suggestion);

  /// 用户对该输出的反馈回调（左滑=忽略，点击=深入，etc）
  Stream<UserFeedback> get feedback;
}

// ── 决策管道 ──

/// 决策链中的一个环节（责任链模式）
abstract class IDecisionFilter {
  /// 返回 null 表示"不拦截"，返回 Decision 表示"拦截并决策"
  Future<Decision?> evaluate(DecisionContext ctx);
}

/// 标准管道：RuleFilter → BudgetGate → LLMDecision
class DecisionPipeline {
  final List<IDecisionFilter> filters;

  Future<Decision> process(DecisionContext ctx) async {
    for (final f in filters) {
      final result = await f.evaluate(ctx);
      if (result != null) return result;
    }
    return Decision.silence();  // 兜底：不说话
  }
}
```

### 依赖注入（禁止 new 分散创建）

```dart
/// 引擎通过构造函数注入所有依赖，不用全局单例
class SuggestionEngine {
  final List<IInputSource> _sources;
  final List<IOutputDriver> _drivers;
  final DecisionPipeline _pipeline;
  final BudgetGate _budget;
  final PetDiaryService _diary;
  final PetMemoryStore _memory;

  SuggestionEngine({
    required List<IInputSource> sources,
    required List<IOutputDriver> drivers,
    required DecisionPipeline pipeline,
    required BudgetGate budget,
    required PetDiaryService diary,
    required PetMemoryStore memory,
  }) : _sources = sources,
       _drivers = drivers,
       _pipeline = pipeline,
       _budget = budget,
       _diary = diary,
       _memory = memory;

  /// 注册新插件（运行时热插拔，MCP/语音等后期接入）
  void registerSource(IInputSource source) {
    if (_sources.any((s) => s.id == source.id)) {
      throw StateError('Source ${source.id} already registered');
    }
    _sources.add(source);
    _sources.sort((a, b) => b.priority.compareTo(a.priority));
  }

  void registerDriver(IOutputDriver driver) {
    _drivers.add(driver);
  }
}
```

### 错误处理分层

```
Layer 1 — 插件级
  单个 InputSource 抛异常 → 捕获，记日志，跳过，不影响其他 Source
  单个 OutputDriver 抛异常 → 捕获，降级到下一个 Driver

Layer 2 — 决策级
  LLM 调用失败 → 纯规则 fallback（已实现）
  连续 3 次失败 → 熔断 10 分钟

Layer 3 — 引擎级
  引擎自身抛异常 → catch，reset，notify 用户（糯糯气泡："哎呀糯糯卡住了..."）
  绝不崩溃
```

```dart
// 插件安全包装器
Future<List<InputSnapshot>> _collectAll(DateTime since) async {
  final results = <InputSnapshot>[];
  for (final source in _sources.where((s) => s.isEnabled)) {
    try {
      final snapshot = await source.collect(since: since)
          .timeout(const Duration(seconds: 5));
      if (snapshot != null) results.add(snapshot);
    } catch (e, stack) {
      PetLogger().error('SuggestionEngine', 'source ${source.id} failed', e);
      // 不影响其他 source
    }
  }
  return results;
}
```

### 测试分层

```
Unit Test（70%）
  · DecisionPipeline 各 filter 独立单元测试
  · BudgetGate 预算计算逻辑
  · InputSnapshot 序列化/反序列化
  · 各 InputSource mock → 返回预置快照

Integration Test（20%）
  · 真实 Hive Box 读写
  · LLM 联调（用 recorded responses 回放）
  · Kotlin ↔ Dart MethodChannel 通信

Widget Test（10%）
  · Token 设置页 UI
  · 建议历史 Tab
  · 气泡交互
```

### 语音（后期）怎么接入

```
语音接入 = 3 个插件注册，不改任何现有代码：

1. VoiceInputSource implements IInputSource
   · ASR 转文字 → InputSnapshot(summary: "用户说：明天提醒我开会")
   · on-device 或 API STT

2. VoiceOutputDriver implements IOutputDriver
   · TTS 读气泡文字
   · L3+ 建议用语音输出

3. 注册到引擎
   engine.registerSource(VoiceInputSource(asrService));
   engine.registerDriver(VoiceOutputDriver(ttsService));

done.
```

### MCP 工具（后期）怎么接入

```
MCP 接入 = 实现 IInputSource + PetTool：

1. McpInputSource implements IInputSource
   · 内部管理多个 PetTool 实例
   · collect() → 汇总所有工具的最近产出

2. PetTool 实例注册
   engine.registerSource(McpInputSource(tools: [
     FileSystemTool(),
     CalendarTool(),
     WebSearchTool(),
   ]));

3. Decision LLM 的 system prompt 自动注入工具列表
   → LLM 可以 decide: {level: L3, topic: "calendar_alert", tool: "calendar"}

done.
```

### 文件结构

```
lib/
├── services/pet/
│   ├── suggestion/
│   │   ├── suggestion_engine.dart        ← 核心协调器
│   │   ├── decision_pipeline.dart        ← 决策管道
│   │   ├── budget_gate.dart              ← 预算门控
│   │   ├── trigger_manager.dart          ← 触发调度
│   │   ├── context_collector.dart        ← 上下文聚合
│   │   │
│   │   ├── sources/
│   │   │   ├── input_source.dart          ← IInputSource 接口
│   │   │   ├── timer_source.dart          ← 定时触发
│   │   │   ├── vision_source.dart         ← 屏幕截图
│   │   │   ├── conversation_source.dart   ← 对话历史
│   │   │   └── time_source.dart           ← 时段感知（纯规则）
│   │   │
│   │   ├── drivers/
│   │   │   ├── output_driver.dart         ← IOutputDriver 接口
│   │   │   ├── bubble_driver.dart         ← 气泡输出
│   │   │   └── chat_driver.dart           ← 聊天框输出
│   │   │
│   │   └── filters/
│   │       ├── decision_filter.dart       ← IDecisionFilter 接口
│   │       ├── rule_filter.dart           ← 纯规则过滤器
│   │       └── llm_decision_filter.dart   ← LLM 决策过滤器
│   │
│   ├── tools/
│   │   ├── pet_tool.dart                  ← PetTool 接口
│   │   └── builtin/                       ← 内置工具（未来）
│   │
│   ├── pet_ai_service.dart               ← 对外门面（不改业务逻辑）
│   ├── pet_diary_service.dart            ← 日记服务
│   └── pet_token_service.dart            ← Token 服务
│
├── models/
│   ├── user_profile.dart                 ← 用户画像
│   ├── suggestion.dart                   ← 建议模型
│   └── input_snapshot.dart               ← 输入快照
│
test/
├── services/pet/suggestion/
│   ├── decision_pipeline_test.dart
│   ├── budget_gate_test.dart
│   ├── sources/
│   │   └── timer_source_test.dart
│   └── drivers/
│       └── bubble_driver_test.dart
```

### 命名与代码规范

```dart
// ✅ 接口用 I 前缀
abstract class IInputSource { ... }

// ✅ 实现类用具体名称
class VisionInputSource implements IInputSource { ... }

// ✅ 工厂方法注册，不直接 new
final engine = SuggestionEngine.create(
  sources: defaultSources,
  drivers: defaultDrivers,
);

// ✅ 所有异步方法带 timeout
Future<InputSnapshot?> collect(...) async {
  return _impl().timeout(Duration(seconds: 5));
}

// ✅ 公开方法返回 Result 类型（不抛裸异常）
// 初期用 try-catch 即可，后期可引入 sealed class Result<T> { Ok, Err }

// ✅ 日志分级
PetLogger().trace()   // 每次 tick
PetLogger().info()    // 每次建议
PetLogger().warn()    // 单次失败
PetLogger().error()   // 连续失败

// ❌ 反模式
// 全局单例（除 Service 层已有的 shared 实例）
// 硬编码字符串（抽到常量或配置）
// 方法 > 50 行（拆子方法）
// class > 300 行（拆文件）
```

---

## 三、触发层（什么时候说话）

### 3.1 触发源

| # | 触发器 | 频率 | Token 成本 | 实现 |
|---|--------|------|-----------|------|
| T1 | 定时轮询 | 5-30 min | 64 tok (decision) | 复用 `startProactiveTimer` |
| T2 | 屏幕快照 | 15-30 min | 512 + 64 tok (vision + decision) | 新增 `ScreenWatcher` |
| T3 | 事件驱动 | 即时 | 64 tok | 监听对话结束/USAGE_STATS |
| T4 | 时段感知 | 定点 | 0 (纯规则) | 本地时间判断 |
| T5 | 回归唤醒 | >3h 不互动后 | 64 tok | 复用 idle 计时器 |

### 3.2 触发频率控制

```
预算感知调度：
 剩余 > 30k  → T1 5min + T2 15min + T3 即时
 剩余 > 10k  → T1 10min + T2 30min + T3 即时
 剩余 > 5k   → T1 30min + T2 关闭 + T3 即时
 剩余 < 5k   → 仅 T4 时段 + T5 唤醒
 剩余 < 1k   → 静默（仅用户主动聊天时响应）
```

### 3.3 静默时段

- 用户设置 `quietUntil`（已有）→ 所有触发暂停
- 角色模式=专注 → 仅 T5 唤醒可用
- 每日 22:00-08:00 → T1-T3 降频到 1/3

---

## 四、上下文层（宠物知道什么）

### 4.1 数据源

| 层级 | 数据 | 存储 | 检索方式 |
|------|------|------|---------|
| **即时** | 当前对话/屏幕场景/今天互动 | Hive + 内存 | 直接读取 |
| **近期** | 本周对话摘要/日记条目 | Hive (pet_memories) | 关键词匹配 |
| **长期** | 用户画像/兴趣标签/重要事实 | Hive (pet_profile 新 box) | LLM 检索 |
| **知识** | 用户喂的文档（Phase 3） | Hive | 向量检索（未来） |

### 4.2 用户画像（pet_profile）

```dart
class UserProfile {
  final Set<String> interests;        // ["编程", "Rust", "原神"]
  final Map<String, int> appUsage;    // {"IDE": 240, "浏览器": 120}  分钟/天
  final List<FactEntry> facts;        // 用户说过的重要事
  final Map<String, double> pref;     // 偏好权重（喜欢直接/反感啰嗦）
  final DateTime updatedAt;
}
```

**提取规则：**
- 每和糯糯聊满 10 轮 → 触发一次 LLM 画像更新（128 tok）
- 画像更新也写一条日记："糯糯今天更了解主人了~ ✨"

### 4.3 情景记忆（扩展 PetMemory）

当前 `PetMemory` 只有 `content + context`。扩展：

```dart
class PetMemory {
  // ...existing fields
  final MemoryTag tag;        // fact | interest | event | reminder
  final double importance;    // 0-1 LLM 评分
  final DateTime? expireAt;   // 提醒类有过期时间
  final int recallCount;      // 被检索次数
}
```

**自动归档：** 每 3 天跑一次 LLM 整理（256 tok），合并冗余记忆，更新重要性。

---

## 五、建议分层（说什么）

### L1 — 闲聊气泡（~16 token）

> "今天天气不错喵~ ☀️"
> "主人在干嘛呀..."

**触发：** 定时轮询，decision 返回 `level=L1`
**输出：** 气泡 3-5s，不记日记
**成本：** 64 (decision) + 32 (chat) ≈ 96 tok/次

### L2 — 场景感知（~64 token）

> "你在写 Flutter 代码呀，记得每 40 分钟起来走走喵~"
> "又在刷淘宝…需要糯糯帮你比价吗？"

**触发：** 屏幕快照 + decision 返回 `level=L2`
**输出：** 气泡 5-8s，自动记日记，点击可进聊天
**成本：** 512 (vision) + 64 (decision) + 128 (chat) ≈ 700 tok/次

### L3 — 深度建议（~256 token）

> "主人，你这两天一直在看租房信息。我帮你整理了筛选条件：预算 3000、朝阳区、一居室。要不要打开备忘录记一下？"
> "上次你说 Python 和 Go 哪个好——我后来查了查，根据你现在的 Flutter 工作流，学 Go 更互补喵。原因：..."

**触发：** 记忆检索命中 + decision 返回 `level=L3`
**输出：** 直接弹聊天 Dialog，完整对话，自动归档记忆
**成本：** 64 (decision) + 300+ (chat) ≈ 400+ tok/次，每天最多 2 次

### L4 — 主动提醒（~128 token）

> "⏰ 主人，10 分钟后有面试！"
> "📊 今日总结：写 4h 代码，刷 2h 手机。糯糯建议明天把刷手机换成看书喵~"

**触发：** 提醒到期 / 每日 21:00 总结
**输出：** 通知栏 + 气泡，自动记日记
**成本：** 64 (decision) + 200 (chat) ≈ 300 tok/次

---

## 六、交付方式

### 6.1 气泡升级

```
现有：气泡出现 → 3 秒消失 → 什么都没了

升级后：
  气泡出现
  ├─ 停留 5-8s（根据层级）
  ├─ 点击 → 弹出迷你聊天，延续话题
  ├─ 左滑 → "知道了" → 记录偏好（以后少说这类）
  ├─ 右滑 → "说详细点" → L2 升级到 L3
  └─ 不操作 → 自动消失，记日记
```

### 6.2 Kotlin 侧改动

气泡点击 → 聊天联动：目前 `showBubble` 只显示文字。新增 `showBubble(text, onClick=true)` —— 点击后调用 `showChatDialog()` 并带上上下文。

```
PetForegroundService.kt 新增命令：
  "showChatBubble" → 气泡 + OnClickListener → showChatDialog(context)
  "showRichBubble"  → 气泡 + 左右滑手势
```

---

## 七、角色模式

用户可说"糯糯进入 XX 模式"，或根据前台 App 自动切换。

| 模式 | system prompt 调整 | 主动频率 | 语气 |
|------|-------------------|---------|------|
| 🐱 陪伴（默认） | 软萌粘人 | 正常 | 句尾"喵~" |
| 🧠 助理 | 直接高效，少卖萌 | 正常 | 无句尾 |
| 🎮 娱乐 | 吐槽段子手 | 正常 | 随意发挥 |
| 📵 专注 | 除非紧急否则闭嘴 | 极低 | — |

**实现：** `PetPersona.mode` 字段 → 切换 system prompt → `PersonaService.update()`

---

## 八、Token 预算模型

### 8.1 每日预算分配（默认 50k/天）

```
┌─────────────────────────────────────────────┐
│ 聊天 (用户主动)        ████████░░  40%  20k  │
│ 主动建议 (D8)          ██████░░░░  30%  15k  │
│ 日记生成 (D1-D2)       ███░░░░░░░  15%  7.5k │
│ 记忆整理 + 画像更新     ███░░░░░░░  15%  7.5k │
└─────────────────────────────────────────────┘
```

### 8.2 成本估算（典型一天）

| 动作 | 次数 | 单次 tok | 日总计 |
|------|------|---------|--------|
| 用户聊天 | 3 轮 | 1000 | 3,000 |
| L1 闲聊气泡 | 6 次 | 96 | 576 |
| L2 场景感知 | 4 次 | 700 | 2,800 |
| L3 深度建议 | 1 次 | 500 | 500 |
| L4 晚间总结 | 1 次 | 300 | 300 |
| 日记润色 | 1 次 | 256 | 256 |
| 记忆整理 | 0.3 次 | 256 | 85 |
| 画像更新 | 0.3 次 | 128 | 43 |
| **总计** | | | **≈7,560 tok/天** |

日常约 7.5k tok，预算 50k 绰绰有余。重度使用约 15-20k。

### 8.3 省钱策略

1. **纯规则 fallback：** 连续 3 次 API 失败 → 降级为纯规则决策（已实现）
2. **L1 本地缓存：** 高频的时段问候语本地预制，不用 LLM
3. **vision 降级：** 预算 < 10k 时关闭屏幕快照
4. **批量决策：** 一次 decision 决定接下来 3 个时段的动作
5. **模型分层：** L1-L2 用 cheap 模型（deepseek-chat），L3-L4 用 deepseek-v4-pro

---

## 九、与日记/记忆的联动

```
┌──────────────┐      ┌──────────────┐
│  PetDiary     │◄─────│  D8 建议引擎  │
│              │ 自动记│              │
│ · AI生成条目  │      │ · L2+ 建议    │
│ · 每日总结    │      │ · 提醒触发    │
│ · 画像更新记  │      │ · 记忆归档    │
│   录          │      │              │
└──────┬───────┘      └──────┬───────┘
       │                     │
       ▼                     ▼
┌──────────────────────────────────────┐
│           ContextCollector           │
│  收集上下文时读取日记 + 记忆作为输入   │
│  "主人昨天熬夜了，今天提醒他早睡"      │
└──────────────────────────────────────┘
```

**联动示例：**

1. 用户 feed 宠物 → `recordEvent('feed')` → 日记："吃了一顿美味大餐~ 😋"
2. D8 检测到用户连续 2 小时看屏幕 → L2 气泡 → 自动记日记："糯糯提醒主人休息眼睛~ 💡"
3. 晚间总结时 ContextCollector 读取今日日记 → 生成摘要 → 写日记：`"今日总结：主人今天写了很多代码，糯糯提醒了 2 次休息~ 📝"`

---

## 十、实现路线

### Phase 2a — 基础：无视觉跑通（1-2 周）

核心理念：不依赖截图，先靠对话+记忆+日记把建议引擎跑通。

| 子任务 | 说明 | 改动范围 |
|--------|------|---------|
| D8a.1 | `TriggerManager` — 多触发源（定时+时段+事件桩） | Dart: new file |
| D8a.2 | `BudgetGate` — 预算感知触发降级 | Dart: new file |
| D8a.3 | `ContextCollector` — 聚合对话+记忆+日记（不含 vision） | Dart: new file |
| D8a.4 | Decision LLM — 接入 PetAgentCore 3 层过滤 | Dart: 改 pet_ai_service |
| D8a.5 | Token 设置页 — 预算滑块 + 功能开关 + 用量仪表盘 | Dart: pet_settings_screen |
| D8b | 气泡→聊天联动 — Kotlin 侧气泡点击弹 Dialog | Kotlin: PetForegroundService |
| D8c | `PetTool` 接口定义 — MCP 工具注册桩，先定义接口 | Dart: new file |

### Phase 2b — 智能（2-3 周）

| 子任务 | 说明 | 改动范围 |
|--------|------|---------|
| D8c.1 | `UserProfile` — 画像数据结构 + 自动提取 | Dart: new file + pet_ai_service |
| D8c.2 | `ContextCollector` — 多源上下文聚合（含日记+记忆） | Dart: new file |
| D8c.3 | L3 深度建议 — 记忆检索 + 画像驱动的对话 | Dart: pet_ai_service |
| D8d | 角色模式 — 模式切换 + system prompt 动态更换 | Dart: pet_persona + pet_ai_service |
| D8e | UX 透明度 — 建议标注来源 + 建议历史页面 | Dart + Kotlin |

### Phase 2c — 完善（3-4 周）

| 子任务 | 说明 | 改动范围 |
|--------|------|---------|
| D8f | 智能提醒 — 时间/模式/机会/总结 | Dart + Kotlin |
| D8g | 气泡手势 — 左滑忽略 / 右滑深入 + 反馈学习 | Kotlin: PetView |
| D8h | 事件驱动触发 — UsageStats / 对话结束回调 | Dart + Kotlin |
| D8i | 隐私信号 + 打扰熔断 — 👁 图标 + 频率熔断器 | Dart + Kotlin |
| D8j | 渐进解锁 — 按使用天数逐步开放功能 | Dart: SuggestionEngine |
| D8k | 情绪可视化 — 建议层级→动画联动 | Dart + Kotlin |
| D8l | 首次引导 — 糯糯自己介绍自己 | Dart: pet_ai_service |

---

## 十一、与 D1-D2（日记）的关系

D1（AI 日记自动生成）和 D2（日记 LLM 润色）是 D8 的**输出管道**：

- D1: L2+ 的建议自动调用 `recordEvent()` → 日记条目
- D2: 每日 21:00 触发一次润色请求，读取今日所有日记 → LLM 以糯糯第一人称写总结

**建议先做 D8a（触发+决策），再做 D1/D2（日记自动+润色），因为 D8a 为 D1 提供了事件源。**

---

## 十二、无视觉模式 — 不用截图照样有用

视觉（屏幕截图分析）是可选增强，不是核心依赖。关了视觉后，糯糯依然能靠以下通道发挥作用：

### 12.1 无视觉时的输入通道

```
通道                  能知道什么                  准确度
──────────────────────────────────────────────────
对话历史              用户最近聊了什么、关心什么     ★★★
宠物日记              今天喂了几次、心情变化        ★★★
互动模式              用户什么时候活跃/冷淡         ★★★
时段感知              早上/中午/晚上/深夜           ★★★
用户画像              兴趣、偏好、重要事实          ★★☆
App 使用统计*          用户在哪些 App 花了时间        ★★☆
剪贴板*               用户复制了什么内容             ★★☆
MCP 工具*             日历/文件/邮件/搜索            ★★★
──────────────────────────────────────────────────
* 未来实现
```

### 12.2 无视觉 vs 有视觉的能力对比

| 能力 | 无视觉 | 有视觉 |
|------|:------:|:------:|
| 时段问候（早安/晚安） | ✅ | ✅ |
| 对话驱动的建议 | ✅ | ✅ |
| 记忆驱动的建议（"你上周说..."） | ✅ | ✅ |
| 日记驱动的关心（"今天还没喂我"） | ✅ | ✅ |
| 知道用户在哪个 App | ❌ | ✅ |
| 知道用户在做什么具体操作 | ❌ | ✅ |
| 提醒休息（基于时间统计） | ✅ | ✅ |
| 提醒休息（基于实时画面） | ❌ | ✅ |
| 看到用户在购物→比价建议 | ❌ | ✅ |

**结论：无视觉时，核心助理能力（记忆/提醒/关心/总结）几乎不受影响。视觉只增强「实时场景感知」这一个维度。**

### 12.3 无视觉模式下的典型一天

```
08:00  L1 早安："早上好！今天周三，上周三你一般 9 点开始工作喵~ ☀️"
       └─ 来源：时段 + 画像（活跃规律）

10:30  L2 关心："你昨天说腰不舒服，坐 1 小时了就起来走走喵~"
       └─ 来源：对话记忆（昨天聊天提到腰痛）

14:00  L2 建议："你上周收藏的 Rust 教程还没看呢，今天有空喵？"
       └─ 来源：情景记忆（用户说过想学 Rust）

18:00  L1 闲聊："到晚饭时间了，今天想吃什么喵~ 🍜"
       └─ 来源：时段

21:00  L4 晚间总结："今天你喂了我 2 次，聊了 3 轮天，
       写了大约 4 小时代码。糯糯觉得今天很充实喵~ 📝"
       └─ 来源：日记 + 互动统计 + 对话摘要
```

一天 5 次互动，全部不需要视觉，总 token ≈ 500。

### 12.4 预算对比

| 模式 | 日 token | 月费估计 | 核心能力 |
|------|---------|---------|---------|
| 无视觉 + 省电 | ~2,000 | ≈ ¥1 | L1 + 时段 + 日记 |
| 无视觉 + 均衡 | ~5,000 | ≈ ¥2 | L1-L4 全开，无实时场景 |
| 有视觉 + 均衡 | ~7,500 | ≈ ¥5 | 全功能 |
| 有视觉 + 全力 | ~15,000 | ≈ ¥10 | 全功能 + 高频 |

---

## 十三、MCP 工具集成（预留架构）

后期接入 MCP 后，糯糯的能力边界会大幅扩展。以下预留对接点：

### 13.1 MCP 工具分类

```
📁 文件系统 → 读取用户文档/笔记/代码
   "你昨天写的 README 有个 typo 喵~"

📅 日历   → 读取日程/会议
   "下午 3 点有周会，要提前准备吗？"

🌐 网页搜索 → 实时信息检索
   "你关注的 Rust 1.90 发布了，要看看更新内容吗？"

📧 邮件   → 未读邮件摘要
   "有 3 封未读邮件，其中 1 封标注了重要"

💻 终端   → 执行命令/查看状态
   "你的 CI 构建失败了，错误在第 42 行"

📋 剪贴板 → 读取复制的内容
   "你刚复制了一个链接，要我帮你总结吗？"
```

### 13.2 架构预留

```dart
/// MCP 工具接口（后期实现）
abstract class PetTool {
  String get name;
  String get description;      // LLM function calling 用
  Map<String, dynamic> get schema; // JSON Schema
  Future<String> execute(Map<String, dynamic> args);
}

/// 注册到 SuggestionEngine
class SuggestionEngine {
  final List<PetTool> _tools = [];

  void registerTool(PetTool tool) {
    _tools.add(tool);
    PetLogger().info('SuggestionEngine', 'tool registered: ${tool.name}');
  }

  // Decision LLM 的 system prompt 自动注入可用工具列表
  String _buildToolPrompt() => _tools.map((t) =>
    '- ${t.name}: ${t.description}').join('\n');
}
```

### 13.3 MCP 触发的建议流

```
用户剪贴板有新内容
  → TriggerManager 检测到剪贴板事件
  → Decision LLM: "用户复制了一个 GitHub 链接，该说话吗？"
  → L2 气泡: "看到你复制了一个 GitHub 链接，要我帮你总结这个项目吗？"
  → 用户点气泡 → 聊天框 → 工具调用 → 结果返回
```

### 13.4 MCP 与无视觉的互补

MCP 恰好弥补了无视觉时最大的盲区——不知道用户在做什么：

```
无视觉 + 无 MCP：只知道用户说过什么
无视觉 + MCP：  知道用户在看什么文件/有什么日程/复制了什么
有视觉 + MCP：  几乎全知（实时画面 + 数据层面）
```

**推荐路径：先做无视觉模式跑通，视觉作为可选增强，MCP 作为后期能力放大器。**

---

## 十四、UX 体验设计

### 12.1 首次引导（Onboarding）

不是一次性弹 3 页引导页，而是糯糯自己介绍自己：

```
Day 1 首次启动：
  糯糯气泡："嗨！我是糯糯，你的桌面助理喵~ ✨"
          "我会偶尔看看你在做什么，然后给你小建议"
          "不想我说话的时候，把我拖到角落就好~"

Day 1 第一次 L2 建议后：
  糯糯气泡："刚才我是看到你在写代码才说的~"
          "以后不想让我看屏幕的话，去设置里关掉「屏幕感知」就行"

Day 3 第一次画像更新后：
  糯糯日记："糯糯发现主人好像喜欢编程和游戏呢~
           以后会多留意这方面的东西喵~ 📝"
```

**原则：** 功能不弹窗介绍，由糯糯用自己的话在合适的时机说出来。

### 12.2 透明度（用户知道糯糯为什么说话）

每次 L2+ 建议附带一句话解释来源：

```
❌ "记得休息喵~"
✅ "我看你连续写了 2 小时代码了 → 记得休息喵~"

❌ "今天天气不错"
✅ "早上好！今天是晴天 → 适合出去走走喵~"
```

**实现：** Decision LLM 输出 `{level, topic, source, text}`，`source` 字段告诉用户信息从哪来。

### 12.3 建议历史（可回溯）

用户可在宠物中心 →「建议历史」Tab 看到糯糯最近说了什么：

```
┌─────────────────────────────────┐
│ 📅 6月5日                       │
│ 💡 14:30  提醒休息（因为写代码）   │
│ 💬 10:15  早上好！              │
│ 📊 08:00  昨日总结              │
│                                 │
│ 📅 6月4日                       │
│ ...                             │
└─────────────────────────────────┘
```

每条可点击 → 进入当时的聊天上下文。

### 12.4 反馈学习（越用越懂你）

用户对建议的反馈形成闭环：

```
用户行为                 →  系统学习

左滑忽略某建议            →  降低该类话题权重 20%
连续 3 次忽略同类建议      →  静默该类话题 7 天
点击气泡深入聊天           →  提升该类话题权重 30%
主动问糯糯某话题           →  加入用户画像兴趣标签
```

**存储：** `UserProfile.pref` 中的偏好权重表，无需 LLM 参与，纯规则更新。

### 12.5 打扰熔断

```
熔断规则（防止骚扰）：
  · 1 小时内 > 3 次建议 → 自动静默 2 小时
  · 用户手动关掉气泡 3 次 → 当天降频 50%
  · 用户在玩游戏/看视频 → 自动延迟建议
  · 检测到用户在通话中（未来） → 完全静默
```

### 12.6 隐私感设计

截图分析是敏感操作，需要让用户感到安全：

```
视觉隐私信号：
  · 截图分析中 → 糯糯头顶出现小眼睛图标 👁（持续 2 秒）
  · 截图仅在内存中 base64 编码，不写入磁盘
  · 设置页显示"最近一次截图分析：X 分钟前"

用户控制：
  · 设置中可查看糯糯最近分析过的屏幕场景摘要（纯文本，不含图）
  · 一键清除所有屏幕分析记录
```

### 12.7 渐进出场（Progressive Disclosure）

功能不是一次性全开，随着使用天数逐步解锁：

```
Day 1   → L1 闲聊 + 基础对话
Day 3   → L2 场景感知（让用户先习惯 2 天）
Day 7   → L4 晚间总结（积累足够数据才有意义）
Day 14  → L3 深度建议（需要画像积累）
Day 30  → 角色模式解锁（用户已充分了解糯糯）
```

**好处：** 新用户不会感觉 overwhelmed，老用户有持续新鲜感。

### 12.8 情绪可视化

糯糯主动说话时，表情/动画配合内容：

```
L1 闲聊   → idle 动画 + 微笑
L2 关心   → wave 动画 + 担心表情
L3 深度   → talking 动画 + 认真表情
L4 提醒   → jump 动画 + 急切表情
危险/警告  → hungry 动画 + 紧张表情
```

**实现：** `cmd('playAnim', {'anim': ...})` 在发气泡的同时调用。

---

## 十五、Token 预算 — 用户自定义

### 13.1 三级预算档位

用户在设置页拖动滑块，实时预览预估行为：

| 档位 | 日预算 | 主动行为 | 预估月费 |
|------|--------|---------|---------|
| 💤 省电 | 5k/天 | 仅 L1 闲聊 + 时段问候 | ≈ ¥2/月 |
| ⚖ 均衡（默认） | 15k/天 | L1 + L2 场景 + 晚间总结 | ≈ ¥5/月 |
| 🚀 全力 | 50k/天 | 全功能 + L3 深度建议 | ≈ ¥15/月 |

### 13.2 设置页 UI

```
┌─────────────────────────────────┐
│ Token 日预算                     │
│ [━━━━━━━━━●━━━━━━━━━━]  15k/天  │
│                                 │
│ 当前档位：⚖ 均衡                │
│ 今日已用：7,560 / 15,000        │
│ 预估月费：≈ ¥5                  │
│                                 │
│ 功能分配：                      │
│ ☑ 主动聊天 (L1)     ~500 tok/天  │
│ ☑ 屏幕感知 (L2)    ~2,800 tok/天 │
│ ☑ 晚间总结 (L4)     ~300 tok/天  │
│ ☐ 深度建议 (L3)     ~500 tok/天  │
│ ☑ 日记自动生成      ~256 tok/天  │
│ ☑ 画像更新          ~128 tok/天  │
└─────────────────────────────────┘
```

每个功能可单独开关。用户拖预算滑块时，功能勾选自动调整（低预算自动关 L3 + Vision）。

### 13.3 实时 Token 仪表盘

宠物中心新增「Token」Tab：

```
今日：████████░░  75% (7,560/10,000)
本周：█████░░░░░  52% (35,000/67,000)
本月：███░░░░░░░  28% (150,000/534,000)

明细：
  主动建议  ██████  2,800
  屏幕分析  ████    1,600
  用户聊天  ██████  2,500
  日记润色  █       256
  记忆整理  █       256
```

### 13.4 超预算保护

```
日预算用尽时：
  → 糯糯变成 💤 状态
  → 仅响应用户主动聊天（不消耗主动建议额度）
  → 气泡提示："糯糯今天的 Token 用完了喵...明天再陪你聊~ 💤"
  → 第二天 00:00 自动重置
```

---

## 十六、风险与限制

| 风险 | 缓解 |
|------|------|
| Token 超支 | 预算门控 + 每日上限硬停 |
| API 失败导致静默 | 纯规则 fallback（已有） |
| 用户觉得烦 | 频度设置（已有 AiFrequency）+ 左滑忽略学习 |
| 视觉模型成本高 | 预算 < 10k 关闭截图，Mimo 模型相对便宜 |
| 隐私（截图分析） | 截图仅在本地 base64 编码后发送 API，不存盘 |
