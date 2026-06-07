# D8 Phase 2a — 无视觉基础引擎 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 SuggestionEngine 协调器，将 KnowledgeBase 上下文注入 PetAgentCore 决策链，实现预算感知的分层建议。

**Architecture:** 增强而非替代。不改 PetAgentCore 和 PetOverlayController 的现有循环逻辑。新建 SuggestionEngine 作为薄协调层，BudgetGate 封装 PetTokenService，通过 PetAgentCore.shared 注入 KnowledgeBase 上下文。

**Tech Stack:** Flutter 3.24 / Dart 3.5 / Hive / 现有 LLMClient + PetTokenService + KnowledgeBase

---

## 文件结构

```
lib/services/pet/suggestion/
├── suggestion_engine.dart         ← 核心协调器：预算门控 + 上下文聚合 → 决策 prompt
├── budget_gate.dart               ← 预算感知：分层降级（全力/均衡/省电/静默）
├── models/
│   └── suggestion.dart            ← Suggestion 数据模型 + SuggestionLevel 枚举
├── sources/
│   └── input_source.dart          ← IInputSource 插件接口（架构预留）
└── drivers/
    └── output_driver.dart         ← IOutputDriver 插件接口（架构预留）

修改文件：
├── lib/services/pet/pet_agent_core.dart   ← _evaluate() 注入 KnowledgeBase 上下文
├── lib/services/pet/pet_overlay_host.dart ← start() 创建 SuggestionEngine + 注入
└── lib/screens/pet/pet_settings_screen.dart ← Token 用量仪表盘

测试文件：
├── test/services/pet/suggestion/budget_gate_test.dart
└── test/services/pet/suggestion/models/suggestion_test.dart
```

---

### Task 1: Suggestion 数据模型 + BudgetGate

**Files:**
- Create: `lib/services/pet/suggestion/models/suggestion.dart`
- Create: `lib/services/pet/suggestion/budget_gate.dart`
- Create: `test/services/pet/suggestion/models/suggestion_test.dart`
- Create: `test/services/pet/suggestion/budget_gate_test.dart`

- [ ] **Step 1: 创建 Suggestion 模型**

```dart
// Flutter 3.24 / Dart 3.5
// lib/services/pet/suggestion/models/suggestion.dart

/// 建议层级（与 D8 设计一致）
enum SuggestionLevel {
  /// L1: 闲聊气泡，~16 tok，定时触发
  l1,

  /// L2: 场景感知，~64 tok，需要上下文
  l2,

  /// L3: 深度建议，~256 tok，需要画像+记忆
  l3,

  /// L4: 主动提醒/总结，~128 tok，定点触发
  l4;

  /// 预估 token 消耗（decision + chat）
  int get estimatedTokens => switch (this) {
    SuggestionLevel.l1 => 96,
    SuggestionLevel.l2 => 200,
    SuggestionLevel.l3 => 500,
    SuggestionLevel.l4 => 300,
  };

  /// 是否仅气泡（不弹聊天框）
  bool get isBubbleOnly => this == SuggestionLevel.l1 || this == SuggestionLevel.l2;
}

/// 一次主动建议
class Suggestion {
  final SuggestionLevel level;
  final String text;
  final String topic;
  final String source; // 上下文来源标注，如 "日记"、"时段"、"记忆"
  final DateTime createdAt;

  const Suggestion({
    required this.level,
    required this.text,
    this.topic = '',
    this.source = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 外壳气泡文本（带来源标注，L2+ 显示为什么说这句话）
  String toBubbleText() {
    if (source.isNotEmpty && level != SuggestionLevel.l1) {
      return '$text （来源：$source）';
    }
    return text;
  }

  Map<String, dynamic> toJson() => {
    'level': level.name,
    'text': text,
    'topic': topic,
    'source': source,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Suggestion.fromJson(Map<String, dynamic> json) => Suggestion(
    level: SuggestionLevel.values.firstWhere(
      (e) => e.name == json['level'],
      orElse: () => SuggestionLevel.l1,
    ),
    text: json['text'] as String? ?? '',
    topic: json['topic'] as String? ?? '',
    source: json['source'] as String? ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}
```

- [ ] **Step 2: 编写 Suggestion 模型测试**

```dart
// Flutter 3.24 / Dart 3.5
// test/services/pet/suggestion/models/suggestion_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/services/pet/suggestion/models/suggestion.dart';

void main() {
  group('SuggestionLevel', () {
    test('estimatedTokens 合理', () {
      expect(SuggestionLevel.l1.estimatedTokens, lessThan(SuggestionLevel.l2.estimatedTokens));
      expect(SuggestionLevel.l3.estimatedTokens, greaterThan(SuggestionLevel.l2.estimatedTokens));
    });

    test('isBubbleOnly', () {
      expect(SuggestionLevel.l1.isBubbleOnly, isTrue);
      expect(SuggestionLevel.l2.isBubbleOnly, isTrue);
      expect(SuggestionLevel.l3.isBubbleOnly, isFalse);
      expect(SuggestionLevel.l4.isBubbleOnly, isFalse);
    });
  });

  group('Suggestion', () {
    test('toJson/fromJson 往返一致', () {
      final s = const Suggestion(
        level: SuggestionLevel.l2,
        text: '记得休息喵~',
        topic: '健康提醒',
        source: '时段+日记',
      );
      final json = s.toJson();
      final restored = Suggestion.fromJson(json);
      expect(restored.level, SuggestionLevel.l2);
      expect(restored.text, '记得休息喵~');
      expect(restored.topic, '健康提醒');
      expect(restored.source, '时段+日记');
    });

    test('toBubbleText L1 不带来源标注', () {
      final s = const Suggestion(
        level: SuggestionLevel.l1,
        text: '早上好喵~ ☀️',
        source: '时段',
      );
      expect(s.toBubbleText(), '早上好喵~ ☀️');
    });

    test('toBubbleText L2+ 带来源标注', () {
      final s = const Suggestion(
        level: SuggestionLevel.l2,
        text: '记得休息喵~',
        source: '时段+日记',
      );
      expect(s.toBubbleText(), contains('来源：时段+日记'));
    });

    test('fromJson 缺字段用默认值', () {
      final s = Suggestion.fromJson({});
      expect(s.level, SuggestionLevel.l1);
      expect(s.text, '');
      expect(s.topic, '');
      expect(s.source, '');
    });
  });
}
```

- [ ] **Step 3: 运行测试确认失败**

```bash
cd c:\Users\lenovo\Desktop\ai-chat-app && C:\flutter\bin\flutter.bat test test/services/pet/suggestion/models/suggestion_test.dart
```

Expected: 部分 FAIL（BudgetGate 尚未实现无关，确保 Suggestion 测试本身能跑）

- [ ] **Step 4: 创建 BudgetGate（闭包注入，零接口）**

```dart
// Flutter 3.24 / Dart 3.5
// lib/services/pet/suggestion/budget_gate.dart
import '../pet_token_service.dart';
import 'models/suggestion.dart';

/// 预算门控：根据剩余 Token 决定允许的建议层级
///
/// 通过闭包注入解耦测试，无需抽象接口。
/// 生产：`BudgetGate(getRemaining: PetTokenService.instance.getBudgetRemaining)`
/// 测试：`BudgetGate.test(remaining: 30000)`
class BudgetGate {
  final Future<int> Function() _getRemaining;

  /// 生产构造 — 注入任意异步查询函数
  BudgetGate({Future<int> Function()? getRemaining})
      : _getRemaining = getRemaining ?? PetTokenService.instance.getBudgetRemaining;

  /// 测试构造 — 固定返回值
  BudgetGate.test({required int remaining})
      : _getRemaining = (() async => remaining);

  /// 获取当前预算允许的最高建议层级
  Future<SuggestionLevel> getAllowedLevel() async {
    final remaining = await _getRemaining();
    if (remaining > 20000) return SuggestionLevel.l4;
    if (remaining > 5000) return SuggestionLevel.l2;
    return SuggestionLevel.l1;
  }

  /// 是否能承担预估 token 消耗
  Future<bool> canAfford(int estimatedTokens) async {
    final remaining = await _getRemaining();
    return remaining >= estimatedTokens;
  }

  /// 是否允许视觉分析（预算 > 10k 才开）
  Future<bool> isVisionAllowed() async {
    final remaining = await _getRemaining();
    return remaining > 10000;
  }

  /// 预算档位 label（供 UI 显示）
  Future<String> getTierLabel() async {
    final remaining = await _getRemaining();
    if (remaining > 20000) return '全力';
    if (remaining > 5000) return '均衡';
    if (remaining > 1000) return '省电';
    return '静默';
  }

  /// 当前剩余 Token
  Future<int> getRemaining() => _getRemaining();
}
```

- [ ] **Step 5: 编写 BudgetGate 测试**

```dart
// Flutter 3.24 / Dart 3.5
// test/services/pet/suggestion/budget_gate_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/services/pet/suggestion/budget_gate.dart';
import 'package:deepseek_chat/services/pet/suggestion/models/suggestion.dart';

void main() {
  group('BudgetGate', () {
    test('剩余 > 20k → L4', () async {
      final gate = BudgetGate.test(remaining: 30000);
      expect(await gate.getAllowedLevel(), SuggestionLevel.l4);
    });

    test('剩余 5k-20k → L2', () async {
      final gate = BudgetGate.test(remaining: 10000);
      expect(await gate.getAllowedLevel(), SuggestionLevel.l2);
    });

    test('剩余 < 5k → L1', () async {
      final gate = BudgetGate.test(remaining: 3000);
      expect(await gate.getAllowedLevel(), SuggestionLevel.l1);
    });

    test('边界值：恰好 20000 → L2', () async {
      final gate = BudgetGate.test(remaining: 20000);
      expect(await gate.getAllowedLevel(), SuggestionLevel.l2);
    });

    test('边界值：恰好 5000 → L2', () async {
      final gate = BudgetGate.test(remaining: 5000);
      expect(await gate.getAllowedLevel(), SuggestionLevel.l2);
    });

    test('canAfford 足够', () async {
      final gate = BudgetGate.test(remaining: 5000);
      expect(await gate.canAfford(500), isTrue);
    });

    test('canAfford 不足', () async {
      final gate = BudgetGate.test(remaining: 200);
      expect(await gate.canAfford(500), isFalse);
    });

    test('canAfford 刚好相等', () async {
      final gate = BudgetGate.test(remaining: 500);
      expect(await gate.canAfford(500), isTrue);
    });

    test('isVisionAllowed > 10k', () async {
      final gate = BudgetGate.test(remaining: 15000);
      expect(await gate.isVisionAllowed(), isTrue);
    });

    test('isVisionAllowed < 10k', () async {
      final gate = BudgetGate.test(remaining: 5000);
      expect(await gate.isVisionAllowed(), isFalse);
    });

    test('getTierLabel 各档位', () async {
      expect(await BudgetGate.test(remaining: 30000).getTierLabel(), '全力');
      expect(await BudgetGate.test(remaining: 10000).getTierLabel(), '均衡');
      expect(await BudgetGate.test(remaining: 3000).getTierLabel(), '省电');
      expect(await BudgetGate.test(remaining: 500).getTierLabel(), '静默');
    });
  });
}
```

- [ ] **Step 6: 运行测试**

```bash
C:\flutter\bin\flutter.bat test test/services/pet/suggestion/budget_gate_test.dart test/services/pet/suggestion/models/suggestion_test.dart
```

Expected: ALL PASS

- [ ] **Step 7: Commit**

```bash
git add lib/services/pet/suggestion/models/suggestion.dart lib/services/pet/suggestion/budget_gate.dart test/services/pet/suggestion/models/suggestion_test.dart test/services/pet/suggestion/budget_gate_test.dart
git commit -m "feat: Suggestion 模型 + BudgetGate 预算门控（闭包注入）"
```

---

### Task 2: 插件接口（IInputSource / IOutputDriver）

**Files:**
- Create: `lib/services/pet/suggestion/sources/input_source.dart`
- Create: `lib/services/pet/suggestion/drivers/output_driver.dart`

纯接口定义，无实现，无测试。为后期视觉/语音/MCP 预留架构锚点。

- [ ] **Step 1: 创建 IInputSource 接口**

```dart
// Flutter 3.24 / Dart 3.5
// lib/services/pet/suggestion/sources/input_source.dart
import '../models/suggestion.dart';

/// Token 消耗等级
enum TokenCostLevel { none, cheap, normal, expensive }

/// 一次上下文采集快照
class InputSnapshot {
  final String sourceId;
  final String summary;          // 供 LLM 阅读的摘要（< 200 字符）
  final Map<String, dynamic>? metadata;
  final DateTime collectedAt;

  const InputSnapshot({
    required this.sourceId,
    required this.summary,
    this.metadata,
    DateTime? collectedAt,
  }) : collectedAt = collectedAt ?? DateTime.now();
}

/// 输入源插件接口：任何能给糯糯提供上下文的来源都实现这个
abstract class IInputSource {
  /// 唯一标识（用于日志/开关/预算计量）
  String get id;

  /// 优先级 0-100（高优先级的上下文被优先消费）
  int get priority;

  /// 是否已启用（受预算/用户设置控制）
  bool get isEnabled;

  /// Token 消耗等级
  TokenCostLevel get costLevel;

  /// 采集上下文，返回 null 表示本轮无新信息
  /// 异步但必须可超时取消（调用方负责 timeout）
  Future<InputSnapshot?> collect({required DateTime since});

  /// 释放资源
  void dispose();
}
```

- [ ] **Step 2: 创建 IOutputDriver 接口**

```dart
// Flutter 3.24 / Dart 3.5
// lib/services/pet/suggestion/drivers/output_driver.dart
import '../models/suggestion.dart';

/// 用户对建议的反馈
enum UserFeedbackType { ignore, click, dismiss, swipeLeft, swipeRight }

class UserFeedback {
  final String suggestionId;
  final UserFeedbackType type;
  final DateTime timestamp;

  const UserFeedback({
    required this.suggestionId,
    required this.type,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// 输出驱动接口：气泡/聊天/通知/语音都实现这个
abstract class IOutputDriver {
  String get id;

  /// 按照层级选择输出方式
  bool canHandle(SuggestionLevel level);

  /// 执行输出
  Future<void> deliver(Suggestion suggestion);

  /// 用户对该输出的反馈流
  Stream<UserFeedback> get feedback;
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/services/pet/suggestion/sources/input_source.dart lib/services/pet/suggestion/drivers/output_driver.dart
git commit -m "feat: IInputSource + IOutputDriver 插件接口（架构预留）"
```

---

### Task 3: SuggestionEngine 协调器

**Files:**
- Create: `lib/services/pet/suggestion/suggestion_engine.dart`
- Create: `test/services/pet/suggestion/suggestion_engine_test.dart`

- [ ] **Step 1: 创建 SuggestionEngine**

```dart
// Flutter 3.24 / Dart 3.5
// lib/services/pet/suggestion/suggestion_engine.dart
import '../pet_logger.dart';
import '../pet_token_service.dart';
import '../knowledge/knowledge_base.dart';
import 'budget_gate.dart';
import 'models/suggestion.dart';
import 'sources/input_source.dart';
import 'drivers/output_driver.dart';

/// 主动建议引擎 — 纯协调器，不持业务逻辑
///
/// 职责：
/// 1. 预算门控：根据剩余 Token 决定允许的建议层级
/// 2. 上下文聚合：从 KnowledgeBase 获取决策上下文
/// 3. 构建增强 prompt：合并上下文 + 预算信息 → 供 PetAgentCore 使用
class SuggestionEngine {
  final KnowledgeBase _kb;
  final BudgetGate _budget;
  final PetTokenService _tokenService;

  SuggestionEngine({
    required KnowledgeBase knowledgeBase,
    BudgetGate? budgetGate,
    PetTokenService? tokenService,
  })  : _kb = knowledgeBase,
        _budget = budgetGate ?? BudgetGate(),
        _tokenService = tokenService ?? PetTokenService.instance;

  BudgetGate get budget => _budget;

  /// 构建决策上下文 prompt — 供 PetAgentCore._evaluate() 注入
  ///
  /// 返回一段可直接拼接到决策 prompt 的文本。
  /// 根据预算自动降级上下文深度。
  Future<String> buildDecisionContext() async {
    final allowedLevel = await _budget.getAllowedLevel();

    // 预算 → 上下文深度映射
    final depth = switch (allowedLevel) {
      SuggestionLevel.l4 || SuggestionLevel.l3 => ContextDepth.deep,
      SuggestionLevel.l2 => ContextDepth.standard,
      SuggestionLevel.l1 => ContextDepth.minimal,
    };

    // 从 KnowledgeBase 获取上下文
    final ctx = await _kb.getDecisionContext(
      level: SuggestionLevel.l4, // 请求最高层级的上下文
      userDepth: depth,          // 实际深度由预算决定
    );

    final sb = StringBuffer();
    sb.writeln('【当前上下文】');
    sb.writeln(ctx.toPromptFragment());

    // 预算信息
    final remaining = await _budget.getRemaining();
    final budgetInfo = await _budget.getTierLabel();
    sb.writeln('预算档位：$budgetInfo（剩余 $remaining tok）');

    PetLogger().trace('SuggestionEngine',
        'buildDecisionContext: depth=$depth budget=$budgetInfo');
    return sb.toString().trim();
  }

  /// 判断当前是否应该生成建议
  Future<bool> shouldSuggest(SuggestionLevel level) async {
    final allowed = await _budget.getAllowedLevel();
    if (level.index > allowed.index) return false;
    return _budget.canAfford(level.estimatedTokens);
  }

  /// 获取当前预算允许的最高层级
  Future<SuggestionLevel> getAllowedLevel() => _budget.getAllowedLevel();

  void dispose() {
    // 当前无资源需释放，保留扩展点
  }
}
```

- [ ] **Step 2: 验证（无独立单元测试）**

SuggestionEngine 是薄协调器，业务逻辑委托给 BudgetGate + KnowledgeBase。通过 Task 6 集成验证保证正确性。如有问题 `flutter analyze` 会在编译期捕获。

- [ ] **Step 3: Commit**

```bash
git add lib/services/pet/suggestion/suggestion_engine.dart test/services/pet/suggestion/suggestion_engine_test.dart
git commit -m "feat: SuggestionEngine — 预算门控 + KnowledgeBase 上下文聚合"
```

---

### Task 4: 注入 PetAgentCore — 决策上下文增强

**Files:**
- Modify: `lib/services/pet/pet_agent_core.dart` — 添加 `SuggestionEngine?` 字段 + `_evaluate()` 增强
- Modify: `lib/services/pet/pet_overlay_host.dart` — `start()` 创建 SuggestionEngine 并注入

- [ ] **Step 1: PetAgentCore 添加 SuggestionEngine 注入点**

在 `lib/services/pet/pet_agent_core.dart` 中：

```dart
// 在 import 区域添加：
import 'suggestion/suggestion_engine.dart';

// 在 PetAgentCore 类中添加字段（放在 tokenService 声明之后）：
SuggestionEngine? _suggestionEngine;

/// 注入建议引擎（由 PetOverlayController 在 KnowledgeBase 初始化后调用）
void attachSuggestionEngine(SuggestionEngine engine) {
  _suggestionEngine = engine;
  PetLogger().info('Agent', 'SuggestionEngine attached');
}
```

修改 `_evaluate()` 方法，在构建 prompt 时注入 KnowledgeBase 上下文：

```dart
// 在 _evaluate() 方法中，prompt 构建部分之前添加：

Future<void> _evaluate({String context = ''}) async {
  if (_decisionClient == null) return;
  await _refreshConfig();

  try {
    await _loadPersona();
    final mood = _mood.applyNoise();

    final prompt = StringBuffer();
    if (context.isNotEmpty) prompt.writeln('当前语境：$context');

    // ── D8: 注入 KnowledgeBase 上下文 ──
    if (_suggestionEngine != null) {
      try {
        final enrichedContext = await _suggestionEngine!.buildDecisionContext();
        if (enrichedContext.isNotEmpty) {
          prompt.writeln(enrichedContext);
        }
      } catch (e) {
        // KnowledgeBase 上下文获取失败不应阻断决策
        PetLogger().warn('Agent', 'buildDecisionContext failed, continuing without enrichment', e);
      }
    }

    prompt.writeln('当前心情：活跃度=${mood.activity.toStringAsFixed(2)} 毒舌度=${mood.sass.toStringAsFixed(2)} 听话度=${mood.compliance.toStringAsFixed(2)}');
    prompt.writeln('决策：你现在想做什么？回复格式：{"action":"bubble/move/flip/speak/silent","content":"..."}');

    // ... 后续不变
```

- [ ] **Step 2: PetOverlayController 创建并注入 SuggestionEngine**

在 `lib/services/pet/pet_overlay_host.dart` 中：

```dart
// 在 import 区域添加：
import 'suggestion/suggestion_engine.dart';
import 'suggestion/budget_gate.dart';

// 在 start() 方法中，KnowledgeBase 创建之后、_aiService!.startProactiveTimer 之前添加：

// ── 创建 SuggestionEngine 并注入 PetAgentCore ──
final suggestionEngine = SuggestionEngine(
  knowledgeBase: _knowledgeBase!,
  budgetGate: BudgetGate(getRemaining: PetTokenService.instance.getBudgetRemaining),
);
PetAgentCore.shared?.attachSuggestionEngine(suggestionEngine);
PetLogger().info('Overlay', 'SuggestionEngine created and attached to PetAgentCore');
```

- [ ] **Step 3: analyze 验证**

```bash
C:\flutter\bin\flutter.bat analyze lib/services/pet/pet_agent_core.dart lib/services/pet/pet_overlay_host.dart
```

Expected: 0 errors

- [ ] **Step 4: Commit**

```bash
git add lib/services/pet/pet_agent_core.dart lib/services/pet/pet_overlay_host.dart
git commit -m "feat: SuggestionEngine 注入 PetAgentCore 决策链"
```

---

### Task 5: Token 用量仪表盘 UI

**Files:**
- Modify: `lib/screens/pet/pet_settings_screen.dart` — 在预算 section 下方添加用量展示

不新建文件，直接在现有 `_buildBudgetSection()` 下方追加一个 `_buildTokenDashboard()` 组件。

- [ ] **Step 1: 添加状态变量和加载逻辑**

在 `_PetSettingsScreenState` 中添加：

```dart
// 新增状态变量（放在 _dailyBudget 之后）：
int _todayUsed = 0;
int _weekUsed = 0;
int _monthUsed = 0;

// 在 _loadBudget() 方法末尾追加：
Future<void> _loadBudget() async {
  try {
    final svc = PetTokenService.instance;
    await svc.loadBudget();
    _dailyBudget = svc.dailyBudget;
    // D8: 加载用量统计
    await _loadUsageStats();
  } catch (_) {}
}

Future<void> _loadUsageStats() async {
  try {
    final svc = PetTokenService.instance;
    final today = await svc.getTodayUsage();
    _todayUsed = today.totalTokens;
    final weekList = await svc.getWeekUsage();
    _weekUsed = weekList.fold(0, (sum, u) => sum + u.totalTokens);
    _monthUsed = await svc.getMonthUsage();
  } catch (_) {}
}
```

- [ ] **Step 2: 编写 Token 仪表盘 Widget**

```dart
// 在 _buildBudgetSection() 方法之后添加：

Widget _buildTokenDashboard() {
  final budget = _dailyBudget ?? 50000;
  final todayPercent = budget > 0 ? (_todayUsed / budget).clamp(0.0, 1.0) : 0.0;
  final color = todayPercent > 0.8
      ? Colors.red
      : todayPercent > 0.5
          ? Colors.orange
          : Colors.green;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      const Text('📊 Token 用量', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      const SizedBox(height: 12),
      // 今日用量条
      Row(
        children: [
          const Text('今日', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: todayPercent,
                minHeight: 10,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(_todayUsed / 1000).toStringAsFixed(1)}k / ${(budget / 1000).toStringAsFixed(0)}k',
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
      const SizedBox(height: 8),
      // 本周 / 本月
      Row(
        children: [
          _buildUsageChip('本周', _weekUsed),
          const SizedBox(width: 12),
          _buildUsageChip('本月', _monthUsed),
        ],
      ),
      // 超预算警告
      if (todayPercent >= 1.0) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
            const SizedBox(width: 4),
            Text(
              '今日预算已用尽，AI 仅响应主动聊天',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ],
    ],
  );
}

Widget _buildUsageChip(String label, int tokens) {
  final k = (tokens / 1000).toStringAsFixed(1);
  return Chip(
    avatar: const Icon(Icons.token_outlined, size: 14),
    label: Text('$label: ${k}k', style: const TextStyle(fontSize: 11)),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}
```

- [ ] **Step 3: 插入到 build() 方法中**

在 `_buildBudgetSection()` 调用后添加 `_buildTokenDashboard()`：

```dart
// 在 build() 的 children 列表中，`_buildBudgetSection()` 之后添加：
_buildTokenDashboard(),
const Divider(height: 32),
```

同时，在 `_buildBudgetSection()` 的 `onChanged` 回调（选择预设额度时）添加刷新用量：

```dart
// 在 ChoiceChip 的 onSelected 回调中，_saveBudget(values[i]) 之后添加：
_saveBudget(values[i]);
_loadUsageStats(); // D8: 刷新用量
```

- [ ] **Step 4: analyze 验证**

```bash
C:\flutter\bin\flutter.bat analyze lib/screens/pet/pet_settings_screen.dart
```

Expected: 0 errors

- [ ] **Step 5: Commit**

```bash
git add lib/screens/pet/pet_settings_screen.dart
git commit -m "feat: Token 用量仪表盘 — 今日/本周/本月 + 进度条"
```

---

### Task 6: 综合验证 + 回归测试

**Files:**
- 无新建，全量验证

- [ ] **Step 1: 全量 analyze**

```bash
C:\flutter\bin\flutter.bat analyze
```

Expected: 0 errors（允许 pre-existing warnings）

- [ ] **Step 2: 全部测试**

```bash
C:\flutter\bin\flutter.bat test
```

Expected: ALL PASS（至少 Suggestion + BudgetGate + SuggestionEngine + PetPersona 测试通过）

- [ ] **Step 3: 检查 pre-existing warnings 无新增**

对比 Phase 2 结束时的 analyze 基线（0 errors, 5 warnings, 12 infos）

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: D8 Phase 2a 综合验证 — analyze + test 全量通过"
```

---

## 实现顺序

```
Task 1 (Suggestion + BudgetGate)
  └→ Task 2 (插件接口，无依赖)
  └→ Task 3 (SuggestionEngine，依赖 Task 1)
      └→ Task 4 (注入 PetAgentCore，依赖 Task 3)
          └→ Task 5 (Token UI，依赖 Task 1 的 BudgetGate)
              └→ Task 6 (综合验证)
```

Task 1 和 Task 2 可并行。Task 2 无测试（纯接口定义）。

## 验证清单

- [ ] `flutter analyze` → 0 errors
- [ ] `flutter test` → ALL PASS
- [ ] BudgetGate 各档位边界正确（>20k L4, 5k-20k L2, <5k L1）
- [ ] SuggestionEngine.shouldSuggest() 预算不足时正确拒绝
- [ ] PetAgentCore._evaluate() 在 SuggestionEngine 注入后能正常完成决策
- [ ] 设置页 Token 仪表盘正确显示用量百分比
- [ ] 无 Kotlin 改动，无 Hive schema 迁移
