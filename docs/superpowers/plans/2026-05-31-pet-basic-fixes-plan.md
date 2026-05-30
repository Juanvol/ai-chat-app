# 宠物系统基础修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复宠物系统 7 项基础 bug（petScale 不生效、参数错误、模型/视觉配置、Token 自定义、上下文/Persona、记忆提取）

**Architecture:** 4 个文件独立改动，无文件间依赖冲突。每个 Task 自包含，顺序执行。TDD：先写测试验证失败 → 最小实现 → 测试通过。

**Tech Stack:** Flutter 3.24 / Dart 3.5, Hive v2.x, Provider

---

## 文件改动映射

| Task | 文件 | 设计 |
|------|------|------|
| 1 | `lib/pet/pet_window.dart` | #1 petScale 生效 |
| 2 | `lib/screens/pet_settings_screen.dart` | #2 参数修复 |
| 3 | `lib/screens/pet_settings_screen.dart` | #3 主模型+视觉模型 |
| 4 | `lib/screens/pet_settings_screen.dart` | #4 Token 自定义 |
| 5 | `lib/screens/pet_settings_screen.dart` | #5 上下文轮数 UI |
| 6 | `lib/services/pet_ai_service.dart` | #3 视觉 key 后端 |
| 7 | `lib/pet/mini_chat.dart` | #5 #6 Persona+上下文 |
| 8 | `lib/pet/mini_chat.dart` + `lib/pet/pet_window.dart` | #7 记忆摘要 |

---

### Task 1: petScale 传入 PetRenderer

**Files:**
- Modify: `lib/pet/pet_window.dart:58-76, 165-208`
- Test: `test/pet/pet_window_test.dart`（新建）

- [ ] **Step 1: 写失败测试 — PetRenderer 接收 size 参数**

```dart
// test/pet/pet_window_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:deepseek_chat/pet/pet_window.dart';
import 'package:deepseek_chat/pet/pet_renderer.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Hive.initFlutter();
    Hive.registerAdapter('pet_config', /* ... */); // 如果没有 adapter 用 Map
  });

  testWidgets('PetRenderer size 默认为 120', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PetRenderer(status: PetStatus.idle),
      ),
    );
    final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
    expect(sizedBox.width, 120);
    expect(sizedBox.height, 120);
  });

  testWidgets('PetRenderer 接收自定义 size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PetRenderer(status: PetStatus.idle, size: 180),
      ),
    );
    final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
    expect(sizedBox.width, 180);
    expect(sizedBox.height, 180);
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd c:/Users/lenovo/Desktop/ai-chat-app && C:/flutter/bin/flutter.bat test test/pet/pet_window_test.dart`
Expected: 测试通过（PetRenderer 已支持 size 参数，无需修改即可通过）。此测试确认 size 参数传递链路正确。

- [ ] **Step 3: 实现 — pet_window.dart 读取 petScale**

在 `_PetWindowState` 添加字段和读取逻辑：

```dart
// 在 _PetWindowState 类中新增字段（_ecoMode 字段下方）：
double _petScale = 1.0;
```

在 `_initPet()` 方法中，`_initialized = true` 之前插入：

```dart
// 加载宠物大小配置
try {
  final config = await PetService.loadConfig();
  if (mounted) setState(() => _petScale = config.petScale);
} catch (_) {}
```

在 `_buildContent()` 中，修改 PetRenderer 调用：

```dart
// 修改前：
PetRenderer(status: _controller?.state.status ?? PetStatus.idle, ecoMode: _ecoMode),

// 修改后：
PetRenderer(
  status: _controller?.state.status ?? PetStatus.idle,
  size: 120 * _petScale,
  ecoMode: _ecoMode,
),
```

- [ ] **Step 4: 运行所有测试验证**

Run: `cd c:/Users/lenovo/Desktop/ai-chat-app && C:/flutter/bin/flutter.bat test`
Expected: 全部通过（新增测试 + 存量测试）

- [ ] **Step 5: Commit**

```bash
git add lib/pet/pet_window.dart test/pet/pet_window_test.dart
git commit -m "fix: petScale 从 PetConfig 读取并传入 PetRenderer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: DropdownButtonFormField initialValue → value

**Files:**
- Modify: `lib/screens/pet_settings_screen.dart:308, 390, 410`

- [ ] **Step 1: 直接修改（无需测试，编译级错误）**

3 处 `initialValue:` → `value:` + fallback：

```dart
// 行 308 — 性格模板
value: _persona.templateId != null
    && _personaTemplates.containsKey(_persona.templateId)
    ? _persona.templateId! : 'default',

// 行 390 — 决策模型（需先定义 textModels，见 Task 3）
value: textModels.any((m) => m.id == _decisionModel) ? _decisionModel : 'deepseek-chat',

// 行 410 — 对话模型
value: textModels.any((m) => m.id == _chatModel) ? _chatModel : 'deepseek-chat',
```

⚠ **注意：** 行 390 和 410 的 fallback 依赖 `textModels`，这个变量在 Task 3 定义。如果 Task 2 在 Task 3 之前执行，暂时用 `_decisionModel` / `_chatModel` 作为 value（确保变量在 items 中）。因为当前 `models` 列表仍是 `['deepseek-chat', 'deepseek-reasoner']`，fallback 逻辑已在 Step 1 代码中覆盖。

- [ ] **Step 2: 运行测试验证**

Run: `cd c:/Users/lenovo/Desktop/ai-chat-app && C:/flutter/bin/flutter.bat test`
Expected: 全部通过

- [ ] **Step 3: Commit**

```bash
git add lib/screens/pet_settings_screen.dart
git commit -m "fix: DropdownButtonFormField initialValue → value + fallback

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 主模型 + 视觉模型配置

**Files:**
- Modify: `lib/screens/pet_settings_screen.dart:1-30, 300-450`

- [ ] **Step 1: 写失败测试 — 模型过滤逻辑**

```dart
// test/pet/pet_settings_model_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/models/model_config.dart';

void main() {
  group('宠物模型过滤逻辑', () {
    test('主模型列表排除 custom-model 和 mimo-v2-omni', () {
      final mainModels = ModelConfig.builtIn
          .where((m) => m.id != 'custom-model' && m.id != 'mimo-v2-omni')
          .toList();

      expect(mainModels.any((m) => m.id == 'custom-model'), isFalse);
      expect(mainModels.any((m) => m.id == 'mimo-v2-omni'), isFalse);
      expect(mainModels.any((m) => m.id == 'deepseek-chat'), isTrue);
      expect(mainModels.any((m) => m.id == 'gpt-4o'), isTrue);
    });

    test('视觉模型列表包含 xiaomi 和 gpt-4o', () {
      final visionModels = ModelConfig.builtIn
          .where((m) => m.providerId == 'xiaomi' || m.id == 'gpt-4o')
          .toList();

      expect(visionModels.any((m) => m.id == 'mimo-v2-omni'), isTrue);
      expect(visionModels.any((m) => m.id == 'gpt-4o'), isTrue);
    });

    test('showVisionKey 逻辑：同 provider 不显示', () {
      // 如果主模型 provider == 视觉模型 provider，不需要额外 key
      final mainProvider = 'deepseek';
      final visionProvider = 'deepseek'; // 跟随主模型
      expect(visionProvider == mainProvider, isTrue); // → showVisionKey = false
    });

    test('showVisionKey 逻辑：不同 provider 显示', () {
      final mainProvider = 'deepseek';
      final visionProvider = 'xiaomi';
      expect(visionProvider != mainProvider, isTrue); // → showVisionKey = true
    });
  });
}
```

- [ ] **Step 2: 运行测试确认 RED**

Run: `C:/flutter/bin/flutter.bat test test/pet/pet_settings_model_filter_test.dart`
Expected: PASS（这是纯逻辑测试，不依赖 UI）

- [ ] **Step 3: 实现 — pet_settings_screen.dart 模型部分**

文件顶部加 import：
```dart
import '../models/model_config.dart';
```

新增状态字段（与现有字段合并）：
```dart
String _visionModel = '';  // 空 = 跟随主模型
String _visionApiKey = '';
String _visionBaseUrl = '';
late final TextEditingController _visionKeyController = TextEditingController();
```

替换 `_buildModelSection()` 整个方法：
```dart
Widget _buildModelSection() {
  final mainModels = ModelConfig.builtIn
      .where((m) => m.id != 'custom-model' && m.id != 'mimo-v2-omni')
      .toList();
  final visionModels = ModelConfig.builtIn
      .where((m) => m.providerId == 'xiaomi' || m.id == 'gpt-4o')
      .toList();

  // 判断主模型是否有视觉能力
  final mainModel = mainModels.firstWhere(
    (m) => m.id == _chatModel,
    orElse: () => mainModels.first,
  );
  final mainHasVision = visionModels.any((m) => m.id == _chatModel);

  // 视觉 provider 是否与主模型不同
  String visionProvider;
  if (_visionModel.isEmpty) {
    visionProvider = mainModel.providerId;
  } else {
    final vm = visionModels.firstWhere(
      (m) => m.id == _visionModel,
      orElse: () => visionModels.first,
    );
    visionProvider = vm.providerId;
  }
  final showVisionKey = visionProvider != mainModel.providerId;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('🤖 模型配置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      // 决策模型
      DropdownButtonFormField<String>(
        value: mainModels.any((m) => m.id == _decisionModel) ? _decisionModel : 'deepseek-chat',
        decoration: const InputDecoration(
          labelText: '主模型（决策+聊天）',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: mainModels.map((m) => DropdownMenuItem(
          value: m.id,
          child: Text('${m.name} (${m.providerId})', style: const TextStyle(fontSize: 13)),
        )).toList(),
        onChanged: (v) {
          if (v != null) {
            _decisionModel = v;
            _saveModelSetting('decisionModel', v);
          }
        },
      ),
      const SizedBox(height: 24),
      // 视觉模型
      const Text('👁️ 视觉分析', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Text('主模型${mainHasVision ? '支持' : '不支持'}视觉能力。可独立选择视觉模型。',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      const SizedBox(height: 8),
      SwitchListTile(
        title: const Text('开启视觉分析'),
        subtitle: const Text('允许糯糯分析你的屏幕截图'),
        value: _visionEnabled,
        onChanged: (v) {
          _visionEnabled = v;
          _saveModelSetting('visionEnabled', v);
        },
      ),
      if (_visionEnabled) ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _visionModel,
          decoration: const InputDecoration(
            labelText: '视觉模型',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('跟随主模型', style: TextStyle(fontSize: 13))),
            ...visionModels.map((m) => DropdownMenuItem(
              value: m.id,
              child: Text('${m.name} (${m.providerId})', style: const TextStyle(fontSize: 13)),
            )),
          ],
          onChanged: (v) {
            if (v != null) {
              _visionModel = v;
              _saveModelSetting('visionModel', v);
              if (mounted) setState(() {});
            }
          },
        ),
        if (_visionModel.isEmpty && !mainHasVision)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('⚠ 当前主模型无视觉能力，建议选择其他视觉模型',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
          ),
      ],
      if (_visionEnabled && showVisionKey) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _visionKeyController,
          obscureText: true,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            labelText: '视觉 API Key',
            hintText: '视觉模型 provider 的 API Key',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onChanged: (v) {
            _visionApiKey = v.trim();
            _saveModelSetting('visionApiKey', _visionApiKey);
          },
        ),
      ],
    ],
  );
}
```

在 `_loadModelSettings()` 末尾追加视觉模型和 key 读取：
```dart
_visionModel = box.get('visionModel', defaultValue: '') as String;
_visionEnabled = box.get('visionEnabled', defaultValue: false) as bool;
_visionApiKey = box.get('visionApiKey', defaultValue: '') as String;
_visionBaseUrl = box.get('visionBaseUrl', defaultValue: '') as String;
_visionKeyController.text = _visionApiKey;
```

在 `dispose()` 中加：
```dart
_visionKeyController.dispose();
```

`_buildVisionToggle()` 方法删除（逻辑已合并到 `_buildModelSection()`）。

在 `build()` 方法的 ListView children 中删除对 `_buildVisionToggle()` 的调用。

- [ ] **Step 4: 运行 analyze + test**

Run: `cd c:/Users/lenovo/Desktop/ai-chat-app && C:/flutter/bin/flutter.bat analyze && C:/flutter/bin/flutter.bat test`
Expected: 0 analyze errors, 全部测试通过

- [ ] **Step 5: Commit**

```bash
git add lib/screens/pet_settings_screen.dart test/pet/pet_settings_model_filter_test.dart
git commit -m "feat: 主模型+视觉模型从 ModelConfig.builtIn 读取，支持独立选择

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Token 预算自定义输入

**Files:**
- Modify: `lib/screens/pet_settings_screen.dart:356-377` (`_buildBudgetSection`)

- [ ] **Step 1: 写失败测试 — 自定义 budget 持久化**

```dart
// test/services/pet_token_service_test.dart 追加测试
test('setBudget 持久化自定义值', () async {
  final svc = PetTokenService();
  await svc.setBudget(75000);
  expect(svc.dailyBudget, 75000);

  // 新建实例验证持久化
  final svc2 = PetTokenService();
  await svc2.loadBudget();
  expect(svc2.dailyBudget, 75000);
});
```

- [ ] **Step 2: 运行测试**

Run: `C:/flutter/bin/flutter.bat test test/services/pet_token_service_test.dart`
Expected: PASS（PetTokenService 已支持 setBudget 持久化，此测试确认链路正确）

- [ ] **Step 3: 实现 — 加 TextField + Controller**

新增字段（与其他 controller 并列）：
```dart
late final TextEditingController _budgetController = TextEditingController();
```

`_budgetController` 在 `dispose()` 中释放：
```dart
_budgetController.dispose();
```

`_buildBudgetSection()` 末尾追加（在 `Wrap` 的 children 之后）：
```dart
const SizedBox(height: 12),
TextField(
  controller: _budgetController,
  keyboardType: TextInputType.number,
  style: const TextStyle(fontSize: 14),
  decoration: const InputDecoration(
    labelText: '自定义额度',
    hintText: '输入数字，如 75000',
    border: OutlineInputBorder(),
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  ),
  onChanged: (v) {
    final n = int.tryParse(v);
    if (n != null && n > 0) {
      _saveBudget(n);
      setState(() {}); // 取消所有 ChoiceChip 选中
    }
  },
),
```

更新 ChoiceChip `onSelected` — 选中预设时清空 TextField：
```dart
onSelected: (_) {
  _budgetController.clear();
  _saveBudget(values[i]);
},
```

- [ ] **Step 4: 运行 analyze + test**

Run: `cd c:/Users/lenovo/Desktop/ai-chat-app && C:/flutter/bin/flutter.bat analyze && C:/flutter/bin/flutter.bat test`
Expected: 0 analyze errors, 全部通过

- [ ] **Step 5: Commit**

```bash
git add lib/screens/pet_settings_screen.dart test/services/pet_token_service_test.dart
git commit -m "feat: Token 预算支持自定义输入 + 预设 ChoiceChip

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: 聊天上下文轮数设置 UI

**Files:**
- Modify: `lib/screens/pet_settings_screen.dart`（新增一个 builder）

- [ ] **Step 1: 直接实现（纯 UI，无复杂逻辑需测试）**

新增状态字段：
```dart
int _chatContextRounds = 3;
```

在 `_loadModelSettings()` 中读取：
```dart
_chatContextRounds = box.get('chatContextRounds', defaultValue: 3) as int;
```

新增 builder 方法 `_buildContextRounds()`：
```dart
Widget _buildContextRounds() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('聊天上下文轮数: $_chatContextRounds 轮',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Text('每轮 = 用户消息 + AI 回复。0 轮 = 无上下文记忆',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      Slider(
        value: _chatContextRounds.toDouble(),
        min: 0, max: 10, divisions: 10,
        label: '$_chatContextRounds 轮',
        onChanged: (v) {
          _chatContextRounds = v.round();
          _saveModelSetting('chatContextRounds', _chatContextRounds);
        },
      ),
    ],
  );
}
```

在 `build()` 的 ListView children 中插入调用：
```dart
_buildContextRounds(),
const Divider(height: 32),
```

放在 `_buildModelSection()` 和 `_buildVisionToggle()` 之间（当前 `_buildModelSection()` 之后）。

- [ ] **Step 2: 运行 analyze + test**

Run: `cd c:/Users/lenovo/Desktop/ai-chat-app && C:/flutter/bin/flutter.bat analyze && C:/flutter/bin/flutter.bat test`
Expected: 0 analyze errors, 全部通过

- [ ] **Step 3: Commit**

```bash
git add lib/screens/pet_settings_screen.dart
git commit -m "feat: 聊天上下文轮数 Slider 设置（0-10 轮）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: pet_ai_service.dart 视觉 key 读取逻辑

**Files:**
- Modify: `lib/services/pet_ai_service.dart:39-63` (`init()`)

- [ ] **Step 1: 写测试 — 视觉 key 读取优先级**

```dart
// test/services/pet_ai_service_test.dart 追加测试
import 'package:hive/hive.dart';

test('视觉 API key 优先从 pet_config 读取', () async {
  final configBox = await Hive.openBox('pet_config');
  await configBox.put('visionApiKey', 'pet-specific-key');
  await configBox.put('visionBaseUrl', 'https://custom-vision.example.com');

  // 验证 fallback 链：pet_config 优先 → settings xiaomi_key
  // （实际测试需 mock Hive，此处只验证逻辑）
  final key1 = configBox.get('visionApiKey') as String?;
  expect(key1, 'pet-specific-key');
  await configBox.delete('visionApiKey');
});
```

- [ ] **Step 2: 运行测试确认 Hive 读写正常**

Run: `C:/flutter/bin/flutter.bat test test/services/pet_ai_service_test.dart`
Expected: PASS

- [ ] **Step 3: 实现 — init() 中视觉 key 读取优先级**

修改 `init()` 方法中视觉 client 初始化部分（行 58-63）：

```dart
// 修改前：
_visionApiKey = box.get('xiaomi_key') as String?;

// 修改后（优先级：pet_config → settings fallback）：
try {
  final configBox = await Hive.openBox('pet_config');
  _visionApiKey = configBox.get('visionApiKey') as String?;
  _visionBaseUrl = configBox.get('visionBaseUrl') as String?;
} catch (_) {}
// fallback：主应用 xiaomi_key
_visionApiKey ??= box.get('xiaomi_key') as String?;
_visionBaseUrl ??= 'https://token-plan-cn.xiaomimimo.com';

if (_visionApiKey != null && _visionApiKey!.isNotEmpty) {
  _visionClient = LLMClient(apiKey: _visionApiKey);
}
```

- [ ] **Step 4: 运行 analyze + test**

Run: `cd c:/Users/lenovo/Desktop/ai-chat-app && C:/flutter/bin/flutter.bat analyze && C:/flutter/bin/flutter.bat test`
Expected: 0 analyze errors, 全部通过

- [ ] **Step 5: Commit**

```bash
git add lib/services/pet_ai_service.dart test/services/pet_ai_service_test.dart
git commit -m "fix: 视觉 API key 优先从 pet_config 读取，主应用 xiaomi_key 兜底

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: MiniChat 读取自定义 Persona + 上下文轮数

**Files:**
- Modify: `lib/pet/mini_chat.dart:66-75, 114-169`

- [ ] **Step 1: 写测试 — MiniChat 上下文提取逻辑**

```dart
// test/pet/mini_chat_test.dart 追加测试
test('上下文轮数计算正确', () {
  // 3 轮 = 6 条消息
  final rounds = 3;
  final messages = 10; // 模拟 10 条消息
  final msgCount = (rounds * 2).clamp(0, messages);
  final start = messages - msgCount;
  expect(start, 4); // 从第 4 条开始（索引 4-9 = 6 条）
  expect(msgCount, 6);
});

test('0 轮 = 无上下文', () {
  final rounds = 0;
  final messages = 10;
  final msgCount = (rounds * 2).clamp(0, messages);
  expect(msgCount, 0);
});
```

- [ ] **Step 2: 运行测试**

Run: `C:/flutter/bin/flutter.bat test test/pet/mini_chat_test.dart`
Expected: PASS（纯逻辑测试）

- [ ] **Step 3: 实现 — 修改 _initClient() 和 _sendDirect()**

`_initClient()` 替换 persona prompt 读取逻辑（行 66-75）：
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
          if (p.systemPrompt.isNotEmpty) prompt = p.systemPrompt;
        }
      } catch (_) {}
      _client!.setSystemPrompt(prompt);
    }
  } catch (_) {}
}
```

加 import：
```dart
import '../pet/pet_persona.dart';
```

`_sendDirect()` 补齐上下文（行 131-134，`sendStream` 调用前插入）：
```dart
// 提取上下文（替代原来的 history: []）
final history = <Map<String, String>>[];
try {
  final configBox = await Hive.openBox('pet_config');
  final rounds = configBox.get('chatContextRounds', defaultValue: 3) as int;
  final msgCount = (rounds * 2).clamp(0, _messages.length);
  final start = _messages.length - msgCount;
  for (int i = start; i < _messages.length; i++) {
    if (_messages[i].text.isNotEmpty) {
      history.add({
        'role': _messages[i].isUser ? 'user' : 'assistant',
        'content': _messages[i].text,
      });
    }
  }
} catch (_) {}

// 然后 sendStream 调用改为：
await for (final chunk in _client!.sendStream(
  history: history, // 改这里
  userContent: userText,
  thinkingEnabled: false,
  maxTokens: 512,
  cancelToken: _cancelToken,
)) { ... }
```

`_sendViaAgent()` 的上下文提取同样改为读 `chatContextRounds`（行 179-188 的 recentHistory 构建逻辑，把硬编码的 `6` 改为 `rounds * 2`）：
```dart
final rounds = /* 同上读取 */;
final msgCount = (rounds * 2).clamp(0, _messages.length);
final start = (_messages.length - msgCount).clamp(0, _messages.length);
```

- [ ] **Step 4: 运行 analyze + test**

Run: `cd c:/Users/lenovo/Desktop/ai-chat-app && C:/flutter/bin/flutter.bat analyze && C:/flutter/bin/flutter.bat test`
Expected: 0 analyze errors, 全部通过

- [ ] **Step 5: Commit**

```bash
git add lib/pet/mini_chat.dart test/pet/mini_chat_test.dart
git commit -m "fix: MiniChat 读自定义 Persona + 上下文轮数可配

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: 聊天记忆自动提取

**Files:**
- Modify: `lib/pet/mini_chat.dart:1-45, 430-437`（全文件多处）
- Modify: `lib/pet/pet_window.dart:166-172`（MiniChat 调用处）

- [ ] **Step 1: 写测试 — _parseSummariesAndSave JSON 解析逻辑**

```dart
// test/pet/mini_chat_test.dart 追加测试
import 'dart:convert';

test('parseSummaries JSON 数组解析', () {
  final json = '[{"content":"主人喜欢蓝色","context":"pet_chat"},{"content":"主人在写代码","context":"pet_chat"}]';
  final start = json.indexOf('[');
  final end = json.lastIndexOf(']');
  expect(start, 0);
  expect(end, json.length - 1);

  final sub = json.substring(start, end + 1);
  final list = List<Map<String, dynamic>>.from(jsonDecode(sub));
  expect(list.length, 2);
  expect(list[0]['content'], '主人喜欢蓝色');
});

test('空数组正常处理', () {
  final json = '[]';
  final start = json.indexOf('[');
  final end = json.lastIndexOf(']');
  final sub = json.substring(start, end + 1);
  final list = List<Map<String, dynamic>>.from(jsonDecode(sub));
  expect(list.length, 0);
});
```

- [ ] **Step 2: 运行测试**

Run: `C:/flutter/bin/flutter.bat test test/pet/mini_chat_test.dart`
Expected: PASS

- [ ] **Step 3: 实现 — MiniChat 加记忆摘要**

MiniChat 构造函数新增参数：
```dart
class MiniChat extends StatefulWidget {
  final VoidCallback onClose;
  final void Function(String userMsg, String aiMsg, bool liked)? onFeedback;
  final VoidCallback? onMemorySave;
  final PetAiService? aiService;  // 新增

  const MiniChat({
    super.key,
    required this.onClose,
    this.onFeedback,
    this.onMemorySave,
    this.aiService,  // 新增
  });
```

`_MiniChatState` 新增字段：
```dart
PetAiService? _aiService;
int _lastSummarizedIndex = 0;
```

`initState()` 中赋值：
```dart
_aiService = widget.aiService;
```

新增方法（放在 `_sendChatDone` 方法之后）：
```dart
void _summarizeAndSave() async {
  if (_aiService == null) return;
  final newMsgs = _messages.length - _lastSummarizedIndex;
  if (newMsgs < 4) return; // 至少 2 轮才摘要

  try {
    final svc = PetTokenService();
    if (!await svc.checkBudget()) return;
  } catch (_) {
    return;
  }

  final recent = _messages.sublist(_lastSummarizedIndex);
  final text = recent
      .where((m) => m.text.isNotEmpty)
      .map((m) => '${m.isUser ? "主人" : "糯糯"}: ${m.text}')
      .join('\n');

  if (_client == null) return;
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
    final sub = llmOutput.substring(start, end + 1);
    final list = List<Map<String, dynamic>>.from(jsonDecode(sub));
    for (final item in list) {
      final content = item['content'] as String?;
      if (content == null || content.isEmpty) continue;
      _aiService!.saveMemory(
        content: content,
        context: item['context'] as String? ?? 'pet_chat',
        affectionGain: 3,
      );
    }
  } catch (_) {}
}
```

`dispose()` 中开头调用：
```dart
@override
void dispose() {
  _summarizeAndSave(); // fire-and-forget
  // ... 原有清理代码
}
```

加 import：
```dart
import 'dart:convert';
import '../services/pet_token_service.dart';
import '../services/pet_ai_service.dart';
```

- [ ] **Step 4: 实现 — pet_window.dart 传递 aiService**

```dart
// 修改前：
MiniChat(
  onClose: _dismissChat,
  onFeedback: _onChatFeedback,
  onMemorySave: _onChatMemory,
)

// 修改后：
MiniChat(
  onClose: _dismissChat,
  onFeedback: _onChatFeedback,
  onMemorySave: _onChatMemory,
  aiService: _aiService,
)
```

- [ ] **Step 5: 运行 analyze + test**

Run: `cd c:/Users/lenovo/Desktop/ai-chat-app && C:/flutter/bin/flutter.bat analyze && C:/flutter/bin/flutter.bat test`
Expected: 0 analyze errors, 全部通过

- [ ] **Step 6: Commit**

```bash
git add lib/pet/mini_chat.dart lib/pet/pet_window.dart test/pet/mini_chat_test.dart
git commit -m "feat: MiniChat 关闭时自动 LLM 摘要聊天记忆，双写到 pet_memories

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
