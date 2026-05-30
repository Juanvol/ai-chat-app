# 宠物系统基础修复设计

> 7 个底层 bug/缺陷修复，涉及 petScale 不生效、参数错误、模型/预算/视觉配置、聊天 Persona/上下文、记忆提取。
> 所有改动互相独立，改动文件不重叠。

---

## 设计 #1：宠物大小调整生效

**根因：** `PetConfig.petScale` 保存/加载正常，但 `PetWindow` 从未读取 `petScale`，`PetRenderer` 始终用默认 `size: 120`。

**文件：** `lib/pet/pet_window.dart`

**改动：**
1. 加状态字段 `double _petScale = 1.0;`
2. `_initPet()` 末尾调用 `PetService.loadConfig()`，取 `petScale` 更新状态
3. `PetRenderer` 调用改为 `size: 120 * _petScale`

```dart
// _initPet() 内，_initialized = true 之前：
final config = await PetService.loadConfig();
if (mounted) setState(() => _petScale = config.petScale);

// _buildContent()：
PetRenderer(
  status: _controller?.state.status ?? PetStatus.idle,
  size: 120 * _petScale,
  ecoMode: _ecoMode,
)
```

**边界：** `petScale` 已 clamp 到 0.5–1.5，size 范围 60–180，安全。

---

## 设计 #2：DropdownButtonFormField 参数修复 + fallback

**根因：** Flutter 的 `DropdownButtonFormField` 没有 `initialValue` 参数，正确参数是 `value`。如果 `value` 不在 `items` 中会运行时 crash。

**文件：** `lib/screens/pet_settings_screen.dart`

**改动：**
- 3 处 `initialValue:` → `value:` + fallback 保护

```dart
// 性格模板（行 308）：
value: _persona.templateId != null
    && _personaTemplates.containsKey(_persona.templateId)
    ? _persona.templateId! : 'default',

// 决策模型（行 390）：
value: textModels.any((m) => m.id == _decisionModel) ? _decisionModel : 'deepseek-chat',

// 对话模型（行 410）：
value: textModels.any((m) => m.id == _chatModel) ? _chatModel : 'deepseek-chat',
```

---

## 设计 #3+#5 统一：主模型 + 视觉模型

**根因：** 宠物模型只硬编码 2 个、视觉模型无选择、视觉 API Key 无配置入口。

**核心逻辑：**
- **主模型**：负责聊天/决策，从 `ModelConfig.builtIn` 过滤纯文本/多模态模型（排除纯视觉专用模型和 custom-model）
- **视觉模型**：默认"跟随主模型"。若主模型有视觉能力 → 共用；若纯文本 → 另选
- **视觉 API Key**：仅视觉模型 provider ≠ 主模型 provider 时显示

**文件：**
- `lib/screens/pet_settings_screen.dart`（模型 UI）
- `lib/services/pet_ai_service.dart`（读取视觉 key 逻辑）
- 新增 `import '../models/model_config.dart';`

**新增状态字段：**
```dart
String _decisionModel = 'deepseek-chat';
String _chatModel = 'deepseek-chat';
String _visionModel = '';  // 空 = "跟随主模型"
bool _visionEnabled = false;
String _visionApiKey = '';
String _visionBaseUrl = '';
```

**过滤逻辑：**
```dart
// 主模型列表：排除纯视觉和自定义占位
final mainModels = ModelConfig.builtIn
    .where((m) => m.id != 'custom-model' && m.id != 'mimo-v2-omni')
    .toList();

// 视觉模型列表：ModelConfig.builtIn 中所有多模态模型（providerId 为 xiaomi 的、id 含 'omni'/'vision' 的、gpt-4o）
// 具体过滤：m.id 匹配 'omni'|'vision'|'mimo-v2' 或 providerId == 'xiaomi' 或 id == 'gpt-4o'
final visionModels = ModelConfig.builtIn
    .where((m) => m.providerId == 'xiaomi' || m.id == 'gpt-4o')
    .toList();
```

**视觉 Key 显示条件：**
```dart
// 仅在视觉模型 provider ≠ 主模型 provider 时显示
final mainProvider = mainModels.firstWhere((m) => m.id == _chatModel).providerId;
final visionProvider = _visionModel.isEmpty
    ? mainProvider
    : visionModels.firstWhere((m) => m.id == _visionModel).providerId;
final showVisionKey = visionProvider != mainProvider;
```

**pet_ai_service.dart 视觉 key 读取逻辑：**
```dart
// init() 中，优先级：
// 1. pet_config box 的 visionApiKey（宠物专用）
// 2. pet_config box 的 visionBaseUrl（自定义端点）
// 3. settings box 的 xiaomi_key（主应用 fallback）
_visionApiKey = configBox.get('visionApiKey') as String?
    ?? box.get('xiaomi_key') as String?;
_visionBaseUrl = configBox.get('visionBaseUrl') as String?
    ?? 'https://token-plan-cn.xiaomimimo.com';
```

**UI 布局：**
```
🤖 主模型
  └─ [Dropdown] mainModels

👁️ 视觉分析
  └─ [Switch] 开启/关闭
  └─ [Dropdown] 视觉模型（"跟随主模型" + visionModels）
  └─ ⚠ 主模型纯文本 + 跟随主模型 → 提示"当前主模型无视觉能力，请选择其他视觉模型"
  └─ 🔑 API Key [TextField]（仅 showVisionKey = true 时显示）
```

---

## 设计 #4：Token 预算自定义

**文件：** `lib/screens/pet_settings_screen.dart`

**新增：**
- `TextEditingController _budgetController`
- 在现有 ChoiceChip 下方加 `TextField`（数字键盘）
- init/dispose 中管理 controller 生命周期

```dart
// _buildBudgetSection 底部追加：
const SizedBox(height: 12),
TextField(
  controller: _budgetController,
  keyboardType: TextInputType.number,
  style: TextStyle(fontSize: 14),
  decoration: InputDecoration(
    labelText: '自定义额度',
    hintText: '输入数字，如 75000',
    border: OutlineInputBorder(),
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  ),
  onChanged: (v) {
    final n = int.tryParse(v);
    if (n != null && n > 0) _saveBudget(n);
  },
),
```

**交互：** 输入自定义值后，自动取消所有 ChoiceChip 选中（预设值不匹配）。选择预设 Chip 后，清空 TextField。

---

## 设计 #5：聊天上下文轮数可自定义

**文件：**
- `lib/screens/pet_settings_screen.dart`（设置 UI）
- `lib/pet/mini_chat.dart`（读取并应用）

**设置 UI：** 在模型配置下方加 Slider
```dart
int _chatContextRounds = 3; // 默认 3 轮

Text('聊天上下文轮数: $_chatContextRounds 轮',
  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
Text('每轮 = 用户消息 + AI 回复。0 轮 = 无上下文记忆', style: C.caption),
Slider(
  value: _chatContextRounds.toDouble(),
  min: 0, max: 10, divisions: 10,
  label: '$_chatContextRounds 轮',
  onChanged: (v) {
    _chatContextRounds = v.round();
    _saveModelSetting('chatContextRounds', _chatContextRounds);
  },
),
```

**MiniChat 读取：**
```dart
// _sendDirect() 和 _sendViaAgent() 中上下文提取：
final configBox = await Hive.openBox('pet_config');
final rounds = configBox.get('chatContextRounds', defaultValue: 3) as int;
final msgCount = (rounds * 2).clamp(0, _messages.length);
final start = _messages.length - msgCount;
// ... 从 start 开始提取 history
```

---

## 设计 #6：MiniChat 读取自定义 Persona

**文件：** `lib/pet/mini_chat.dart`

**改动：** `_initClient()` 从 Hive `pet_config` box 读取 `persona`，替换硬编码 `_personaPrompt`

```dart
Future<void> _initClient() async {
  try {
    final box = await Hive.openBox('settings');
    final apiKey = box.get('api_key') as String?;
    if (apiKey != null && apiKey.isNotEmpty) {
      _client = LLMClient(apiKey: apiKey);
      // 读自定义 persona，无则 fallback 默认
      String prompt = _personaPrompt;
      try {
        final configBox = await Hive.openBox('pet_config');
        final raw = configBox.get('persona');
        if (raw != null) {
          final p = PetPersona.fromJson(Map<String, dynamic>.from(raw as Map));
          prompt = p.systemPrompt;
        }
      } catch (_) {}
      _client!.setSystemPrompt(prompt);
    }
  } catch (_) {}
}
```

---

## 设计 #7：聊天记忆自动提取

**触发时机：** MiniChat 关闭时（`dispose()` 中，`onClose` 前），取新消息 → LLM 摘要 → 存入 pet_memories。

**防重复：** 记录 `int _lastSummarizedIndex = 0`，只提取 index 之后的新消息。

**Token 预算保护：** 调 `PetTokenService.checkBudget()` 检查，超预算跳过。

**写入方式：** 复用 `PetAiService.saveMemory()`，双写到 pet_memories 和主应用 memories。

**文件：** `lib/pet/mini_chat.dart` + `lib/pet/pet_window.dart`

**pet_window.dart 改动：** 将 `_aiService` 传给 MiniChat
```dart
// pet_window.dart — MiniChat 调用处：
MiniChat(
  onClose: _dismissChat,
  onFeedback: _onChatFeedback,
  onMemorySave: _onChatMemory,
  aiService: _aiService, // 新增
)
```

**mini_chat.dart 新增方法：**
```dart
PetAiService? _aiService;
int _lastSummarizedIndex = 0;

// 在构造函数中接收 _aiService

Future<void> _summarizeAndSave() async {
  if (_aiService == null) return;
  final newMsgs = _messages.length - _lastSummarizedIndex;
  if (newMsgs < 4) return; // 至少 2 轮才摘要

  final svc = PetTokenService();
  if (!await svc.checkBudget()) return;

  final recent = _messages.sublist(_lastSummarizedIndex);
  final text = recent
      .where((m) => m.text.isNotEmpty)
      .map((m) => '${m.isUser ? "主人" : "糯糯"}: ${m.text}')
      .join('\n');

  try {
    final result = await _client!.send(
      history: [],
      userContent: '从以下宠物对话中提取关键信息（用户喜好、宠物状态变化、重要事件），'
          '以 JSON 数组格式返回，不超过 3 条，每条包含 "content" 和 "context" 字段：\n$text',
      maxTokens: 256,
      thinkingEnabled: false,
    );

    _parseSummariesAndSave(result.content);
    _lastSummarizedIndex = _messages.length;
  } catch (_) {}
}

void _parseSummariesAndSave(String llmOutput) {
  try {
    final start = llmOutput.indexOf('[');
    final end = llmOutput.lastIndexOf(']');
    if (start == -1 || end == -1) return;
    final json = llmOutput.substring(start, end + 1);
    // 手动解析 JSON 数组，不引入额外依赖
    // ... 逐条调用 _aiService!.saveMemory(content: ..., context: ...)
  } catch (_) {}
}
```

**调用点：** `dispose()` 中 `widget.onClose()` 之前：
```dart
@override
void dispose() {
  _summarizeAndSave(); // 先摘要
  // ... 原有清理逻辑
  super.dispose();
}
```

---

## 文件改动汇总

| 文件 | 设计 | 改动类型 |
|------|------|---------|
| `lib/pet/pet_window.dart` | #1, #7 | 修改 ~15 行 |
| `lib/pet/mini_chat.dart` | #6, #7 | 修改 ~40 行 |
| `lib/screens/pet_settings_screen.dart` | #2, #3, #4, #5 | 修改 ~60 行 |
| `lib/services/pet_ai_service.dart` | #3 | 修改 ~10 行 |

## 不涉及的文件

- `lib/models/model_config.dart` — 只读，不改
- `lib/pet/pet_config.dart` — 不新增字段
- `lib/pet/pet_renderer.dart` — 不改（通过 size 参数接收）
- `lib/services/pet_chat_service.dart` — 不改

## 验证标准

1. `flutter analyze` 0 error
2. `flutter test` 全部通过
3. 每个设计对应 1-2 个单元/widget 测试
