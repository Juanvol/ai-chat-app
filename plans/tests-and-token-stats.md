# Tests + Token 用量统计 — 实施计划

> 生成时间: 2026-05-27 | 模式: 直接（无 git）| 审查: 已通过

## 总览

两个功能分 7 步，**Phase A（测试）先做**，验证现有行为不破坏；**Phase B（Token 统计）在后**，依赖 Phase A 的 Service 测试保证修改安全。

| 步 | 功能 | 涉及文件 | 预计复杂度 |
|----|------|----------|-----------|
| 1 | 模型层测试扩展 | `test/model_test.dart` | 低 |
| 2 | Service 层测试 | `test/*_service_test.dart`, `test/fake_*.dart` | 中 |
| 3 | Widget 层测试 | `test/*_widget_test.dart` | 中 |
| 4 | TokenUsage 模型 + 定价 | `lib/models/token_usage.dart`, `lib/models/model_config.dart` | 低 |
| 5 | API 层捕获 usage | `lib/api/deepseek_client.dart`, `lib/services/conversation_service.dart`, `lib/services/storage_service.dart` | 中 |
| 6 | TokenStatsService 分析层 | `lib/services/token_stats_service.dart`, `lib/main.dart` | 中 |
| 7 | 用量统计 UI | `lib/screens/token_stats_screen.dart`, `lib/screens/settings_screen.dart` | 中 |

---

## Phase A: 测试

### Step 1 — 模型层测试扩展

**目标**: 覆盖所有 6 个数据模型的 toJson/fromJson 及边界情况。

**文件**: `test/model_test.dart`（重命名自 `widget_test.dart`，保留原有 3 组测试）

**任务**:
- [ ] Message: 默认值（reasoningContent=''）、copyWith 全部字段、toJson/fromJson
- [ ] Conversation: messageCount 排除 streaming 消息、空消息列表往返
- [ ] ModelConfig: builtIn 非空且 id 唯一、providers 非空
- [ ] FeedbackEntry: 默认 processed=false、toJson/fromJson 往返
- [ ] Memory: importance 默认值 3、tags 空列表不丢失、toJson/fromJson
- [ ] Persona: defaultPersona 工厂方法、copyWith 链、fullPrompt 拼接正确

**验证**: `flutter test test/model_test.dart` 全绿

---

### Step 2 — Service 层测试

**目标**: 测试业务逻辑层。由于 ConversationService 依赖具体类 StorageService / LLMClient（无抽象接口），采用**手写 Fake**方案，不引入 mockito。

**新增文件**:
- `test/fake_storage_service.dart` — FakeStorageService（内存 Map 模拟 Hive Box，包含所有 CRUD 方法）
- `test/fake_llm_client.dart` — FakeLLMClient（可配置的 Stream<StreamChunk> 返回值，模拟正常流/错误流/取消流）
- `test/conversation_service_test.dart`
- `test/storage_service_test.dart`
- `test/memory_service_test.dart`
- `test/persona_service_test.dart`
- `test/feedback_service_test.dart`

**FakeStorageService 设计要点**:
- 所有数据存内存 `Map<String, Map<String, dynamic>>`
- `saveConv` / `getConvs` / `delConv` 完整模拟（含 JSON 备份路径可设为 null 跳过）
- settings 用 `Map<String, dynamic>` 存储，`get()` 返回 `defaultValue`
- 构造函数可预填充数据（测试初始化用）

**FakeLLMClient 设计要点**:
- `sendStream()` 返回预设的 `Stream<StreamChunk>` 列表
- 可配置 `cancelToken` 行为（中途取消）
- 可配置 `throwException`（模拟网络错误）
- 可配置 `usage` 返回值（为 Step 5 做准备）

**ConversationService 测试覆盖**:
- [ ] 构造函数加载对话列表、恢复 currentConversation
- [ ] `createConversation` — 插入列表头、设为 current、通知
- [ ] `selectConversation` / `deleteConversation` — current 切换正确
- [ ] `renameConversation` — 标题更新 + updatedAt 刷新
- [ ] `sendMessage` — 无 API Key 时插入提示消息（不崩溃）
- [ ] `sendMessage` — 流式 chunk 逐条追加到 assistant message
- [ ] `sendMessage` — cancel 后消息内容正确（"已停止生成" 或 content）
- [ ] `sendMessage` — 异常时显示友好错误消息
- [ ] `stopGeneration` — cancelToken 不置 null（catch 块依赖）
- [ ] `refreshFromStorage` — 合并后 currentConversation 恢复

**StorageService 测试覆盖**（部分测试可用真实 Hive，部分用 Fake）:
- [ ] `_openBoxSafe` — 三重防御逻辑
- [ ] `saveConv` + `getConvs` 往返（含消息列表）
- [ ] `delConv` — Hive + JSON 备份同步删除
- [ ] `saveMem/getMem/getMems/delMem`
- [ ] `savePersona/getPersona/getPersonas/delPersona`
- [ ] `saveFb/getFbs/getUnprocessedFbs/delFb`
- [ ] settings save/get（String/int/double/bool）

**MemoryService / PersonaService / FeedbackService**:
- [ ] add → notifyListeners → 列表包含新条目
- [ ] delete → 列表移除
- [ ] promptText 拼接（MemoryService）
- [ ] selectAndSave → selPersonaId 持久化（PersonaService）
- [ ] delete 不少于 1 个 persona（PersonaService）
- [ ] autoGenerate → 所有 pending 标记 processed（FeedbackService）

**验证**: `flutter test test/conversation_service_test.dart` 等全部通过

---

### Step 3 — Widget 层测试

**目标**: UI 渲染和交互。所有 Widget 测试需包裹在 `MaterialApp` + 必要的 Provider 中。

**测试 harness 约定**:
```dart
Widget buildTestWidget(Widget child, {ConversationService? svc, ...}) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: svc ?? FakeConversationService()),
        ...
      ],
      child: Scaffold(body: child),  // Scaffold 提供 SnackBar 等上下文
    ),
  );
}
```

**新增文件**:
- `test/chat_input_test.dart`
- `test/chat_bubble_test.dart`
- `test/home_screen_test.dart`

**ChatInput 测试**:
- [ ] 空输入时发送按钮灰色（无 gradient）、不可点击
- [ ] 输入文字后按钮变蓝色 gradient
- [ ] `loading=true` 显示红色停止按钮，点击触发 onStop
- [ ] 点击发送后 `onSend` 回调参数正确、输入框清空
- [ ] 键盘 TextInputAction.send 触发发送

**ChatBubble 测试**:
- [ ] 用户消息右对齐（MainAxisAlignment.end）
- [ ] AI 消息左对齐、显示 AI 头像图标
- [ ] Markdown 粗体/标题/列表渲染
- [ ] 代码块显示语言标签 + 复制图标
- [ ] 深度思考卡片显示 thinking 内容
- [ ] streaming 消息显示三点加载动画

**HomeScreen 测试**:
- [ ] `currentConversation == null` 显示 Welcome 页 + 建议问题列表
- [ ] `currentConversation != null` 显示聊天视图 + AppBar 标题
- [ ] Drawer 列出所有对话标题
- [ ] 点击建议问题触发 `createConversation` + `sendMessage`

**验证**: `flutter test test/chat_input_test.dart` 等全部通过

---

## Phase B: Token 用量统计

### Step 4 — TokenUsage 模型 + 定价配置

**目标**: 新增数据模型 + 每个模型的输入/输出定价。

**新增文件**: `lib/models/token_usage.dart`

```dart
class TokenUsage {
  final String id;              // 毫秒时间戳
  final String conversationId;  // 所属对话
  final String modelId;         // 模型配置 id（如 'ds-v4-pro'）
  final String providerId;      // provider id
  final int promptTokens;
  final int completionTokens;
  final DateTime createdAt;

  int get totalTokens => promptTokens + completionTokens;
  Map<String, dynamic> toJson() => {...};
  factory TokenUsage.fromJson(Map<String, dynamic> json) => ...;
}
```

**修改文件**: `lib/models/model_config.dart`

ModelConfig 新增两个字段 + currency:
```dart
final double inputPricePerM;   // 每百万 token 价格
final double outputPricePerM;
final String currency;         // 'USD' | 'CNY'
```

定价填充策略：
- DeepSeek 官方: USD（V4 Pro $0.28/$0.84, Flash $0.14/$0.42）
- OpenAI: USD（GPT-4o $2.50/$10, 4o-mini $0.15/$0.6, o3-mini $1.1/$4.4, 4.1 $2/$8）
- 硅基流动: CNY（DeepSeek V3 ¥1/¥2, R1 ¥1/¥4, Qwen 免费/¥1 等）
- 智谱: CNY（GLM-4 Plus ¥50/¥50, Flash 免费）
- Moonshot: CNY（v1-8k ¥12/¥12, v1-128k ¥60/¥60）
- 自定义模型: 价格 0 / currency 'USD'（用户无法预设）

**验证**: `flutter test test/model_test.dart` — 追加 TokenUsage toJson/fromJson + ModelConfig 定价非负

---

### Step 5 — API 层捕获 usage

**目标**: 流式和非流式请求均捕获 token 用量，持久化到 StorageService。

**关键技术点**: DeepSeek API 的 `usage` 在 SSE JSON **顶层**（`json['usage']`），不在 `choices[0].delta` 内。出现在 `finish_reason: "stop"` 的那个 chunk（此时 delta 可能为 `{}`），紧接着 `[DONE]`。

**`send()` 非流式也有 usage**: HTTP 响应 `response.data['usage']` 同样在顶层。

**修改 1 — `StreamChunk`** (`lib/api/deepseek_client.dart`):
```dart
class StreamChunk {
  final String text;
  final bool isThinking;
  final Map<String, int>? usage;  // 顶层 json['usage']，仅最终 chunk 有值
  const StreamChunk(this.text, {this.isThinking = false, this.usage});
}
```

**修改 2 — `sendStream()`** 解析逻辑：
- 在现有 delta 解析之后，加一行 `final usage = json['usage'] as Map<String, dynamic>?;`
- 如果有 usage（通常和 `finish_reason: "stop"` 一起出现），yield `StreamChunk('', usage: {'prompt_tokens': ..., 'completion_tokens': ..., 'total_tokens': ...})`
- 此时 delta content 可能为空，所以 text 为空字符串

**修改 3 — `send()`** 返回值新增 usage：
```dart
Future<({String content, String reasoning, Map<String, int>? usage})> send({...})
```
从 `response.data['usage']` 提取。

**修改 4 — `ConversationService.sendMessage()`**:
- `sendStream` 循环中：判断 `chunk.usage != null`，缓存到变量 `finalUsage`
- 流结束后（try 块末尾）：`await _storage.saveUsage(finalUsage, ...)`
- 这是**直接调用 StorageService 的 saveUsage**，等 Step 6 TokenStatsService 创建后会从 Storage 读取

**修改 5 — `StorageService`** 新增 usage 存储：
- `init()` 中加 `_usageBox = await _openBoxSafe('token_usage');`
- `saveUsage(Map<String, int> usage, String convId, String modelId, String providerId)` — 创建 TokenUsage 并存入
- `getUsages()` → `List<TokenUsage>`

**验证**: 现有所有测试通过，`flutter analyze` 零 warning

---

### Step 6 — TokenStatsService 分析层

**目标**: 封装用量查询、聚合、费用估算逻辑。

**新增文件**:
- `lib/services/token_stats_service.dart`
- `test/token_stats_service_test.dart`

**TokenStatsService extends ChangeNotifier**:
```dart
class TokenStatsService extends ChangeNotifier {
  final StorageService _storage;
  List<TokenUsage> get usages => _storage.getUsages();

  // 聚合查询
  int get totalPromptTokens;
  int get totalCompletionTokens;
  int get totalTokens;

  // 按模型分组
  Map<String, List<TokenUsage>> get usageByModel;

  // 最近 N 天每日统计 → 用于折线/柱状图
  List<({DateTime date, int tokens, int count})> dailyStats(int days);

  // 费用估算（调用 ModelConfig 定价）
  double costForModel(String modelId);     // 某模型总费用
  double get totalCostUSD;                 // 全部折合美元
  Map<String, double> get costByModel;     // {modelId: cost}

  // 刷新（从 Storage 重新加载）
  void refresh();
}
```

**费用货币处理**:
- `costForModel` 返回原始货币价格
- `totalCostUSD` 内部做汇率换算（CNY → USD 用硬编码汇率 ~7.2，注释标注"近似汇率，非实时"）
- UI 显示时标注货币符号（$ / ¥）

**修改 `main.dart`**: 注册 `TokenStatsService` Provider（放在 ConversationService 之后）

**验证**: `flutter test test/token_stats_service_test.dart` 全绿

---

### Step 7 — 用量统计 UI

**目标**: 设置页入口 → 用量仪表盘。

**新增 `lib/screens/token_stats_screen.dart`**:

页面结构：
- AppBar: "用量统计"
- 总览区（Card）：3 个数字卡片 — 总 Token 数 / 请求次数 / 估算费用
- 按模型分组（ListView）：每个模型一行 — 名称 + token 数 + 费用
- 7 天趋势图：`CustomPaint` 简易柱状图（7 根柱子 + 日期标签），**不引入第三方图表库**
- 空状态：无用量数据时居中显示"暂无用量数据，发送消息后自动记录"

**修改 `lib/screens/settings_screen.dart`**:
- 在设置列表中添加一项"用量统计"，点击 `Navigator.push` → `TokenStatsScreen`

**验证**: Widget smoke test（渲染不崩溃）+ 手动发送消息验证数据正确

---

## 依赖关系

```
Step 1 ──→ Step 2 ──→ Step 3
                ↓
Step 4 ──→ Step 5 ──→ Step 6 ──→ Step 7
```

- Step 1-2 可部分并行（模型测试不依赖 Fake 层）
- Step 3 依赖 Step 2（Fake 类确定后 Widget 测试使用同一套 Fake）
- Step 4 可与 Phase A 完全并行
- Step 5 依赖 Step 2（Service 测试兜底）+ Step 4（TokenUsage 模型）
- Step 6 依赖 Step 4（TokenUsage 模型）+ Step 5（StorageService 已有 usage 方法）
- Step 7 依赖 Step 6

## 回滚策略

| 步骤 | 回滚方式 |
|------|---------|
| Step 1-3 | 删除测试文件 |
| Step 4 | 删除 `token_usage.dart` + 还原 `model_config.dart` |
| Step 5 | StreamChunk.usage 是 optional 字段，删掉 usage 解析代码即可；StorageService 新增方法无调用方时无害 |
| Step 6 | 删除 `token_stats_service.dart` + 还原 `main.dart` |
| Step 7 | 删除 `token_stats_screen.dart` + 还原 `settings_screen.dart` |

## 不变式（每步完成后验证）

- `flutter analyze` 零 warning
- 所有已有测试通过
- 新加测试全部通过
