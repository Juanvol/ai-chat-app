# 宠物日记、记忆、人格系统 — 设计 Spec

> 2026-06-05 | D1-D2 + Memory + Persona · Phase 2 养成深化

## 零、范围

本 spec 覆盖三个相互依赖的系统：

| 系统 | 职责 | 一句话 |
|------|------|--------|
| **Diary（日记）** | 记录"今天发生了什么" | 事件→高亮→日总结 |
| **Memory（记忆）** | 提炼"主人是什么样的人" | 规则提取+LLM整理→用户画像 |
| **Persona（人格）** | 定义"糯糯是什么样的宠物" | 性格维度→说话风格→AI行为 |

三者关系：

```
Persona ──→ 定义 AI 说话方式
                │
Diary ────→ 提供原始事件燃料 ──→ Memory ──→ 提供用户画像燃料 ──→ D8 AI 决策
```

---

## 一、架构总览

```
┌──────────────────────────────────────────────────────────────┐
│                      KnowledgeBase                            │
│                   (对外门面，构造函数注入)                       │
│                                                              │
│  ┌────────────────────────┐  ┌──────────────────────────┐   │
│  │    DiaryStore           │  │    MemoryStore            │   │
│  │    (领域服务)            │  │    (领域服务)              │   │
│  │                         │  │                           │   │
│  │ ┌───────────────────┐  │  │ ┌──────────────────────┐  │   │
│  │ │ IDiaryRepository   │  │  │ │ IMemoryRepository    │  │   │
│  │ │ (接口)             │  │  │ │ (接口)               │  │   │
│  │ └────────┬──────────┘  │  │ └─────────┬────────────┘  │   │
│  │          │              │  │           │               │   │
│  │ ┌────────▼──────────┐  │  │ ┌─────────▼────────────┐  │   │
│  │ │ DiaryRepoHive      │  │  │ │ MemoryRepoHive       │  │   │
│  │ │ (Hive 实现)        │  │  │ │ (Hive 实现)          │  │   │
│  │ └───────────────────┘  │  │ └──────────────────────┘  │   │
│  └────────────────────────┘  └──────────────────────────┘   │
│                                                              │
│  事件流: DiaryStore.onEventRecorded → MemoryStore.extract()   │
│                                                              │
│  人格层: Persona ──→ buildSystemPrompt() ──→ D8 Decision LLM  │
└──────────────────────────────────────────────────────────────┘
```

### 大厂级架构规范（对齐 D8 spec §二-B）

| D8 spec 规范 | 日记/记忆/人格应用 |
|-------------|-------------------|
| 插件式接口 (`I`前缀) | `IDiaryRepository` / `IMemoryRepository` |
| DI 构造函数注入 | `KnowledgeBase({required diary, required memory})` |
| 责任链 | Diary: event → highlight(规则) → summary(LLM) |
| 错误分层 | Repo抛异常捕获 → 领域级LLM失败fallback → 门面级绝不崩 |
| 热插拔 | 后期换 SQLite 只需实现新 Repo，不改 Store |
| 测试金字塔 | Repo mock 单测 + Store mock 单测 + Hive Box 集成 |

### 文件结构

```
lib/
├── services/pet/
│   ├── knowledge/                           ← 统一知识库（新增）
│   │   ├── knowledge_base.dart              ← 对外门面
│   │   │
│   │   ├── diary/
│   │   │   ├── diary_repository.dart        ← IDiaryRepository 接口
│   │   │   ├── diary_repository_hive.dart   ← Hive 实现
│   │   │   ├── diary_store.dart             ← 领域服务：记录/高亮/日总结
│   │   │   └── diary_summarizer.dart        ← LLM 日总结 prompt 模板
│   │   │
│   │   ├── memory/
│   │   │   ├── memory_repository.dart       ← IMemoryRepository 接口
│   │   │   ├── memory_repository_hive.dart  ← Hive 实现
│   │   │   ├── memory_store.dart            ← 领域服务：提取/整理/过期/用户CRUD
│   │   │   ├── memory_extractor.dart        ← 规则提取（统计类，无LLM）
│   │   │   └── memory_organizer.dart        ← LLM 整理 prompt 模板
│   │   │
│   │   └── models/
│   │       ├── diary_entry.dart             ← 日记数据模型
│   │       ├── memory_entry.dart            ← 记忆数据模型
│   │       └── user_profile.dart            ← 用户画像
│   │
│   ├── persona/
│   │   ├── pet_persona.dart                 ← 人格模型 + systemPrompt 构建
│   │   ├── persona_store.dart               ← 人格持久化服务
│   │   └── persona_mapper.dart              ← 用户数据→初始人格映射
│   │
│   └── skin/
│       └── skin_config.dart                 ← 皮肤配置 + 默认人格
```

### 错误分层

```
Layer 1 — Repo 级
  单个 Hive 读写失败 → 捕获，记日志，返回空列表/fallback
  DIARY_SAVE_ERROR: catch → PetLogger.error() → 不影响交互响应

Layer 2 — 领域级
  LLM 日总结失败 → 跳过今日总结，不阻塞后续
  LLM 记忆整理失败 → 跳过本轮，等 3 天后重试
  连续 3 次失败 → 降级为仅规则模式，通知用户

Layer 3 — 门面级
  KnowledgeBase 自身抛异常 → catch，返回 minimal context
  绝不崩溃
```

---

## 二、数据模型

### DiaryEntry

```dart
// Flutter 3.24 / Dart 3.5
enum DiaryEntryType { event, highlight, summary }

class DiaryEntry {
  final String id;            // 唯一标识
  final DiaryEntryType type;  // 事件/高亮/日总结
  final String content;       // 糯糯第一人称文本
  final String mood;          // emoji 心情
  final String? sourceType;   // 事件来源: feed/pet/tap/talk/suggestion/...
  final DateTime date;        // 发生时间
  final DateTime? dateKey;    // 所属日期 (yyyy-MM-dd)，null 则按 date 归日

  // 构造函数、copyWith、toJson、fromJson
}
```

### MemoryEntry

```dart
// Flutter 3.24 / Dart 3.5
enum MemoryTag { fact, habit, interest, event, reminder }
enum MemorySource { rule, llm }

class MemoryEntry {
  final String id;
  final MemoryTag tag;        // 分类标签
  final String content;       // "主人通常在凌晨2点后睡觉"
  final double importance;    // 0.0–1.0，越高越不会被过期清理
  final int recallCount;      // 被检索命中的次数
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;  // null = 永不过期（重要记忆）
  final MemorySource source;  // 来源：规则提取 / LLM 提取
  final String? sourceDiaryId;// 关联的日记条目 ID
  final String? linkedTo;     // 关联的其它 Memory ID，逗号分隔（Phase C）

  // 构造函数、copyWith、toJson、fromJson
}
```

### UserProfile（轻量版）

```dart
// Flutter 3.24 / Dart 3.5
class UserProfile {
  final String name;                     // 用户名字（如有）
  final List<String> interests;          // 兴趣标签: ["编程", "咖啡", "游戏"]
  final Map<String, double> habitWeights;// 习惯权重: {"lateNight": 0.8, "longCoding": 0.6}
  final List<String> recentTopics;       // 最近聊过的话题（FIFO 10条）
  final DateTime updatedAt;

  // 构造函数、copyWith、toJson、fromJson
}
```

### 设计决策

| 决策 | 理由 |
|------|------|
| `importance` 用 double 非 int | 衰减/升权用小数更精确 |
| `MemorySource` 区分 rule/llm | 规则提取不耗 token，预算门控需要知道每条记忆的成本 |
| `UserProfile` 纯规则聚合 | 不单独跑 LLM 生成画像，从 Memory 中规则聚合 |
| `habitWeights` 用 Map 非固定字段 | 习惯种类不可预知，固定字段 = 改 schema 频繁 |
| `linkedTo` 预留 | Phase C 跨域关联用，B 阶段不实现 |

---

## 三、日记系统

### 数据流

```
用户交互(tap/feed/pet/chat)
        │
        ▼
  recordEvent(type, detail)         ← 现有入口，不动
        │
        ▼
  DiaryStore.record(event)
        │
        ├──→ 写 Hive (DiaryEntry, type=event)
        │
        ├──→ 规则检测：高亮？
        │       │  心情剧烈变化 / 稀有互动 / 连续3h未休息
        │       │  是 → 写高亮条目 (DiaryEntry, type=highlight)
        │       │
        │       ▼
        └──→ 发出回调: onEventRecorded → MemoryStore.extract(event)
```

### 日总结（21:00 触发，LLM，Phase 2b）

```
DiarySummarizer.summarize(today)
        │
        ├──→ 聚合今日所有 event + highlight
        ├──→ 构造 prompt（~256 tok）：
        │     "以下是糯糯今天的日记事件：
        │      09:15 被主人戳了一下
        │      10:30 糯糯提醒主人休息眼睛
        │      14:22 和主人聊了会 Rust
        │      ...
        │      请用糯糯软萌的语气写一篇日记总结，不超过150字。"
        │
        ├──→ LLM 生成 → 写 Hive (DiaryEntry, type=summary)
        │
        └──→ 预算不足 → 跳过，不阻塞
```

### 接口

```dart
// Flutter 3.24 / Dart 3.5
abstract class IDiaryRepository {
  Future<void> save(DiaryEntry entry);
  Future<List<DiaryEntry>> loadByDate(DateTime date);
  Future<List<DiaryEntry>> loadRecent({int days = 7});
  Future<void> delete(String id);
  Future<void> clearAll();
  Stream<DiaryEntry> watch();
}

class DiaryStore {
  final IDiaryRepository _repo;
  final PetTokenService _token;
  final void Function(DiaryEntry event)? onEventRecorded;  // 回调：通知 MemoryStore

  Future<void> recordEvent(String type, {String? detail});
  DiaryEntry? _detectHighlight(DiaryEntry event, List<DiaryEntry> recentEvents);
  Future<DiaryEntry?> summarizeDay(DateTime date);  // null = 预算不足
}
```

### 高亮规则（纯规则，不耗 token）

| 条件 | 规则 | 示例 |
|------|------|------|
| 心情急剧下降 | 1h 内 mood 降 ≥ 40 | "糯糯今天心情突然变差了..." |
| 稀有互动 | 30 天未出现的互动类型 | "主人第一次喂糯糯吃这个~ ✨" |
| 连续屏幕 | 3h+ 无交互 | "主人已经连续看了3小时屏幕了..." |
| 深夜活动 | 凌晨 1-5 点互动 | "凌晨3点主人还在工作..." |

---

## 四、记忆系统

### 双通道提取

```
┌─────────────────────────────────────────────────────────┐
│                    记忆提取（双通道）                       │
│                                                         │
│   DiaryStore.onEventRecorded                            │
│         │                                               │
│         ▼                                               │
│   MemoryExtractor (规则)     MemoryOrganizer (LLM)       │
│   实时、免费                  每3天批量、耗 token          │
│   ════════════               ════════════════            │
│   · 时间戳统计                 · 去重合并                  │
│   · 计数累积                   · 模式发现                  │
│   · 频次阈值 → habit           · 重要性重评估              │
│   · 关键词 → interest          · 过时记忆降权/归档         │
│                                                         │
│         └─────────┬───────────┘                         │
│                   ▼                                     │
│            MemoryStore ←── 用户编辑 ←── UI               │
│                   │                                     │
│                   ▼                                     │
│            UserProfile (聚合视图)                        │
└─────────────────────────────────────────────────────────┘
```

### 规则提取（实时、免费）

| 事件条件 | 提取规则 | 产出 MemoryEntry |
|---------|---------|-----------------|
| tap 凌晨 1-5 点 | 累计 ≥ 5 次/月 | `{tag: habit, content: "主人经常深夜工作"}` |
| talk 含关键词 | 关键词命中 | `{tag: interest, content: "主人对Rust感兴趣"}` |
| suggestion L3+ | 直写 | `{tag: event, content: "某日糯糯建议...", importance: 0.5}` |
| feed/pet | 仅计数 | 不单独写，由 LLM 整理时汇总模式 |
| 任意稀有 | 30天首次出现 | `{tag: fact, content: "主人第一次做X"}` |

### LLM 整理（每 3 天，~256 tok）

```
MemoryOrganizer.organize(recentMemories)
        │
        ├──→ 输入：最近 3 天的记忆 + 高频规则未覆盖的事件
        ├──→ Prompt：
        │     "以下是糯糯最近对主人的观察片段：
        │      [规则提取的记忆]
        │      [高频事件]
        │      请做以下工作，输出 JSON：
        │      1. 去重合并相似的记忆
        │      2. 发现规律模式
        │      3. 调整重要性
        │      4. 标记过期记忆"
        │
        ├──→ LLM 返回 JSON → 批量更新
        └──→ 预算不足(剩余<500 tok) → 跳过
```

### 接口

```dart
// Flutter 3.24 / Dart 3.5
abstract class IMemoryRepository {
  Future<void> save(MemoryEntry entry);
  Future<void> saveAll(List<MemoryEntry> entries);
  Future<List<MemoryEntry>> loadAll({MemoryTag? tag});
  Future<List<MemoryEntry>> search(String keyword);
  Future<void> delete(String id);
  Future<void> update(String id, MemoryEntry entry);
  Future<void> clearAll();
  Stream<List<MemoryEntry>> watch();
}

class MemoryStore {
  final IMemoryRepository _repo;
  final PetTokenService _token;
  final MemoryExtractor _extractor;    // 规则，无 LLM
  final MemoryOrganizer _organizer;    // LLM，需预算

  Future<void> extractFrom(DiaryEntry event);
  Future<void> organizeIfNeeded();

  // ⭐ 用户 CRUD
  Future<void> updateMemory(String id, {String? content, double? importance, MemoryTag? tag});
  Future<void> deleteMemory(String id);
  Future<void> addMemory(String content, MemoryTag tag);

  // 用户画像聚合（纯规则）
  UserProfile buildProfile();

  // 数据迁移
  Future<String> exportJson();
  Future<void> importJson(String json);
}
```

### 用户可调整的记忆

| 操作 | UI 入口 | 说明 |
|------|---------|------|
| 修改内容 | 记忆详情 → 编辑 | "主人喜欢咖啡"→"主人喜欢手冲咖啡" |
| 调整重要性 | 星标/拖拽 | 重要记忆置顶、不过期 |
| 改分类 | 下拉选 tag | fact↔interest↔habit... |
| 删除 | 左滑删除 | 错误记忆直接删 |
| 手动添加 | FAB 按钮 | "主人下周要考试"→手动写 reminder |

---

## 五、KnowledgeBase → AI 分层上下文

### 用户可控的深度偏好

```
设置页 → AI 助手深度：
  □ 省电模式    仅时段+计数 (0 tok/决策)
  ○ 标准模式    画像+近期记忆 (~80 tok/决策)
  □ 深度模式    全量上下文 (~200 tok/决策)

  ⚠ 深度模式每月多消耗 ~6k token
```

### 层级 → 深度 → Token 映射

| 建议层级 | 默认深度 | 上下文内容 | 额外 token | 建议质量 |
|---------|---------|-----------|-----------|---------|
| L1 卖萌气泡 | minimal | 时段 + 互动计数 | 0 | "主人早啊~ ☀️" |
| L2 场景气泡 | standard | + 画像摘要 + 近期记忆 | ~80 | "你已看3h屏幕，休息一下吧~" |
| L3 深度意见 | deep | + 日记摘要 + 习惯模式 | ~200 | "上次你说想学Rust，有个新闻..." |
| L4 主动提醒 | deep | + 全量记忆检索 | ~200 | "主人明天要开会，记得准备~" |

### 接口

```dart
// Flutter 3.24 / Dart 3.5
enum ContextDepth { minimal, standard, deep }

class KnowledgeBase {

  /// D8 决策引擎调用
  Future<DecisionContext> getDecisionContext({
    required SuggestionLevel level,
    required ContextDepth userDepth,
  });

  /// L3 深度检索
  Future<List<MemoryEntry>> searchMemories(String query, {int limit = 5});

  /// 完整用户画像（UI展示）
  UserProfile getUserProfile();
}
```

### 决策上下文示例

**minimal (0 tok):**
> "现在是上午10点。今天主人互动了3次。"

**standard (~80 tok):**
> "现在是下午3点。主人今天互动了8次。主人喜欢编程、咖啡。主人有深夜工作习惯。最近主人提到过想学Rust。"

**deep (~200 tok):**
> "现在是晚上11点。主人今天连续编码5小时，互动12次。主人喜欢编程、咖啡、独立游戏。主人常年凌晨2点睡觉。本周主人提到3次Rust、2次腰疼。糯糯今天提醒过主人休息2次，只点开1次。昨天主人心情似乎不太好，日记写了'好累'。"

---

## 六、人格系统

### 架构

```
┌────────────────────────────────────────────────────────────┐
│                      Persona 层                             │
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │  Skin 皮肤    │───→│  Persona 人格 │───→│  AI 行为     │  │
│  │  (视觉)      │    │  (性格设定)   │    │  (说话方式)   │  │
│  └──────────────┘    └──────┬───────┘    └──────────────┘  │
│                             │                               │
│            ┌────────────────┼────────────────┐              │
│            ▼                ▼                ▼              │
│     systemPrompt      speakingStyle      traits            │
│     (LLM 系统提示)     (语气/口癖)       (性格维度)         │
└────────────────────────────────────────────────────────────┘
```

### 数据模型

```dart
// Flutter 3.24 / Dart 3.5
class PetPersona {
  final String name;              // 宠物名字，用户可改
  final String species;           // 物种：猫/狗/兔/自定义
  final String systemPrompt;      // LLM 系统提示词（可由 trait 拼装）
  final SpeakingStyle style;      // 说话风格
  final PersonalityTraits traits; // 性格维度
  final String? source;           // 来源：builtin / skin_default / user_custom
}

class SpeakingStyle {
  final String selfReference;     // 自称："糯糯" / "本喵" / "咱"
  final String sentenceEnding;    // 句尾："喵~" / "汪!" / "..."
  final int maxSentenceLength;    // 最大句子长度（字符数）
  final double emojiFrequency;    // emoji 使用频率 0.0-1.0
  final double cuteLevel;         // 软萌程度 0.0-1.0
}

class PersonalityTraits {
  final double energy;            // 活力 0.0-1.0
  final double curiosity;         // 好奇心 0.0-1.0
  final double clinginess;        // 粘人度 0.0-1.0
  final double tsundere;          // 傲娇度 0.0-1.0
  final double empathy;           // 共情力 0.0-1.0
  final double humor;             // 幽默感 0.0-1.0
}
```

### 人格来源链（优先级从高到低）

| 优先级 | 来源 | 说明 |
|--------|------|------|
| 1 | 用户自定义 | 设置页手动调整每个 trait 滑块 |
| 2 | 用户数据推断 | 初次启动时根据用户提供的偏好生成初始 persona |
| 3 | 皮肤默认 | 每个皮肤自带默认 persona（如"黑猫皮肤→tsundere+0.6"） |
| 4 | 内置默认 | 弗糯糯（软萌粘人猫）作为 fallback |

### 用户数据 → 初始人格

```
初次启动可选填：
  "你希望宠物是什么性格？"
  □ 活泼好动 → energy: 0.8, clinginess: 0.7
  □ 安静陪伴 → energy: 0.2, clinginess: 0.3
  □ 傲娇毒舌 → tsundere: 0.8, cuteLevel: 0.3
  □ 温柔治愈 → empathy: 0.9, humor: 0.3

  "你平时多在什么时间活动？"
  □ 早睡早起 → 糯糯也早睡早起
  □ 正常作息 → 跟随用户
  □ 夜猫子   → 深夜活跃度 +0.5
```

### Persona → systemPrompt

```dart
// Flutter 3.24 / Dart 3.5
String buildSystemPrompt(PetPersona persona) => '''
你是${persona.name}，一只${persona.species}。
性格：${persona.traits.describe()}
自称"${persona.style.selfReference}"，句尾加"${persona.style.sentenceEnding}"。
${persona.style.cuteLevel > 0.5 ? '用软萌可爱的语气说话' : '用简洁直接的语气说话'}
${persona.traits.curiosity > 0.6 ? '喜欢主动问主人问题' : '安静陪伴，不多话'}
${persona.traits.tsundere > 0.3 ? '偶尔口是心非，明明关心却说反话' : ''}
${persona.traits.empathy > 0.7 ? '擅长察觉主人情绪变化，适时关心' : ''}
保持${persona.style.maxSentenceLength}字以内。
''';
```

### 皮肤联动（未来扩展）

```dart
// Flutter 3.24 / Dart 3.5
class SkinConfig {
  final String id;
  final String displayName;      // "黑猫"
  final String spritePath;       // 精灵图路径
  final PetPersona defaultPersona;// 皮肤默认人格
  final List<String> animations; // 支持的动画列表
}
```

**用户换皮肤 → 加载该皮肤的默认 persona → 用户可在默认基础上微调。**

---

## 七、Token 预算

### 日消耗估算

| 操作 | 频率 | 每次 tok | 日消耗 | 月消耗 |
|------|------|---------|--------|--------|
| 日记事件记录 | ~20次/天 | 0 (规则) | 0 | 0 |
| 日记日总结 | 1次/天 | ~256 | 256 | 7.7k |
| 记忆规则提取 | ~20次/天 | 0 (规则) | 0 | 0 |
| 记忆 LLM 整理 | 0.33次/天 | ~256 | 85 | 2.6k |
| **知识库基础消耗** | | | **~340/天** | **~10k/月** |

### AI 决策附加消耗（按用户深度设置）

| 深度 | 每次决策 tok | 日决策次数 | 日消耗 | 月消耗 |
|------|------------|-----------|--------|--------|
| 省电 | 0 | ~10次 | 0 | 0 |
| 标准 | ~80 | ~10次 | 800 | 24k |
| 深度 | ~200 | ~10次 | 2,000 | 60k |

### 分档总览

| 档位 | 日预算 | 知识库基础 | AI决策 | 合计/天 | 余量 |
|------|--------|----------|--------|---------|------|
| 省电 5k | 5,000 | ~340 | 0 | ~340 | 93% |
| 标准 15k | 15,000 | ~340 | ~800 | ~1,140 | 92% |
| 深度 50k | 50,000 | ~340 | ~2,000 | ~2,340 | 95% |

---

## 八、实现分阶段

### Phase 1: 数据层 + 领域服务核心（本次）

```
D1.1  DiaryEntry 模型 + IDiaryRepository + DiaryRepoHive
D1.2  DiaryStore（event 记录 + 高亮检测）
D2.1  MemoryEntry 模型 + IMemoryRepository + MemoryRepoHive
D2.2  MemoryStore + MemoryExtractor（规则提取 + 用户 CRUD）
D3.1  UserProfile 模型 + 聚合逻辑
D4.1  KnowledgeBase 门面（聚合查询 + getDecisionContext）
D5.1  PetPersona 重构（traits + style + buildSystemPrompt）
D6.1  改造 PetOverlayController._recordDiary → DiaryStore
```

### Phase 2: LLM 能力 + UI（下轮）

```
D1b.1 DiarySummarizer（LLM 日总结）
D2b.1 MemoryOrganizer（LLM 整理）
D3b.1 日记列表 UI
D3b.2 记忆管理 UI（列表 + 编辑 + 手动添加）
D3b.3 人格设置 UI（traits 滑块 + 风格选择）
D3b.4 D8 ContextCollector 接入 KnowledgeBase
```

### Phase 3: 完整版（Phase C，B 稳定后评估）

```
D1c.1 日记多日周报
D2c.1 记忆自动关联（linkedTo）
D3c.1 个人成长时间线 UI
D3c.2 兴趣标签权重自动衰减
D3c.3 日记情绪曲线
```

---

## 九、与 D8 spec 的衔接点

| D8 spec 引用 | 本 spec 实现 |
|-------------|------------|
| §四 ContextCollector — 日记摘要输入 | KnowledgeBase.getDecisionContext() |
| §四 ContextCollector — 用户画像输入 | UserProfile + buildProfile() |
| §四 ContextCollector — 宠物记忆输入 | MemoryStore → search() + loadAll() |
| §九 日记联动 — L2+ 自动记日记 | DiaryStore.recordEvent() |
| §九 记忆联动 — 建议归档记忆 | MemoryStore.extractFrom() |
| §八 预算表 — 日记生成 15% | DiarySummarizer + MemoryOrganizer |
| §八 预算表 — 记忆整理 15% | 合并入 MemoryOrganizer |
| §六 角色模式 — system prompt 切换 | Persona.buildSystemPrompt() |

---

## 十、方案 C 预留（记忆）

方案 C（完整版）内容已记录至 memory/project_diary_memory_plan_c.md，包括：
- 日记多日周报（每周末 LLM 生成）
- 记忆自动关联（LLM 发现跨域关联）
- 个人成长时间线 UI
- 兴趣标签权重自动衰减（30天降权/60天归档）
- 日记情绪曲线（mood score 0-100）

触发条件：B 运行稳定 ≥ 2 周 + D8 L3-L4 已验证 + Token 预算有余量。
