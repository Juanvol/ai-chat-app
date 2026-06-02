# Phase 1 优化 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 宠物中心可互动 + 首页/设置拆分为小组件 + 全面接入 Provider 实时状态管理

**Architecture:** 3 个独立子项目（A: 宠物中心 / B: 首页拆分 / C: 设置拆分），19 个 Task，~800 行新代码，16 新建 + 5 修改

**Tech Stack:** Flutter 3.45 / Dart 3.13 / Provider / Hive

---

## 文件结构

```
lib/
├── main.dart                                🔧 注册 PetController Provider
├── widgets/
│   ├── pet_hero_card.dart                   🆕 宠物卡片
│   ├── pet_status_bars.dart                 🆕 2×2 进度条
│   ├── pet_action_bar.dart                  🆕 5 操作按钮
│   ├── pet_info_chips.dart                  🆕 Token/统计 chip
│   ├── home_welcome.dart                    🆕 空状态欢迎页
│   ├── home_drawer.dart                     🆕 抽屉
│   ├── home_chat_view.dart                  🆕 聊天列表
│   ├── home_model_selector.dart             🆕 模型选择
│   ├── home_search_sheet.dart               🆕 搜索
│   ├── home_message_menu.dart               🆕 消息菜单
│   ├── settings_enable_section.dart         🆕 启用/频率
│   ├── settings_appearance_section.dart     🆕 皮肤/大小
│   ├── settings_persona_section.dart        🆕 性格
│   ├── settings_model_section.dart          🆕 模型配置
│   ├── settings_token_section.dart          🆕 预算
│   └── settings_debug_section.dart          🆕 调试日志
├── pet/
│   └── pet_controller.dart                  🔧 +pet() 方法
└── screens/
    ├── pet_center_screen.dart               🔧 组装新组件
    ├── home_screen.dart                     🔧 引用拆分组件
    └── pet_settings_screen.dart             🔧 引用 Section
```

---

## 子项目 A：宠物中心 UI 升级

### Task A1: PetController — 注册为 Provider + 添加 pet()

**Files:**
- Modify: `lib/pet/pet_controller.dart:195-199`
- Modify: `lib/main.dart:45-53`

- [ ] **Step 1: PetController 添加 pet() 方法**

在 `pet_controller.dart` 的 `play()` 方法后添加：

```dart
// Flutter 3.24 / Dart 3.5
void pet() {
  _cancelTransition();
  _markInteraction();
  _state = _state.copyWith(
    mood: (_state.mood + 10).clamp(0, 100),
    status: PetStatus.happy,
    affection: _state.affection + 5,
    totalInteractions: _state.totalInteractions + 1,
  );
  PetLogger().trace('Controller', 'pet -> happy, mood=' + _state.mood.toString());
  _notify();
  _scheduleTransition(PetStatus.idle, const Duration(seconds: 3));
}
```

- [ ] **Step 2: main.dart 注册 PetController Provider**

在 `MultiProvider` 的 `providers` 列表添加（line 53 之后）：

```dart
ChangeNotifierProvider(create: (_) => PetController()),
```

同时添加 import：
```dart
import 'pet/pet_controller.dart';
```

- [ ] **Step 3: 运行测试验证**

```bash
flutter test
```
预期：289 测试全部通过

- [ ] **Step 4: Commit**

```bash
git add lib/pet/pet_controller.dart lib/main.dart
git commit -m "feat: PetController 注册 Provider + 添加 pet() 摸摸方法

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task A2: PetHeroCard — 宠物头像卡片

**Files:**
- Create: `lib/widgets/pet_hero_card.dart`

- [ ] **Step 1: 创建 PetHeroCard**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pet/pet_controller.dart';

class PetHeroCard extends StatelessWidget {
  const PetHeroCard({super.key});

  String _stageName(int interactions) => interactions < 30 ? '初识' : interactions < 200 ? '熟悉' : interactions < 1000 ? '默契' : '老友';
  String _levelName(int interactions) => interactions < 30 ? 'Lv.1' : interactions < 200 ? 'Lv.2' : 'Lv.3';

  @override
  Widget build(BuildContext context) {
    return Consumer<PetController>(
      builder: (context, ctrl, _) {
        final s = ctrl.state;
        final moodEmoji = s.mood > 60 ? '😊' : s.mood > 30 ? '😐' : '😞';
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              children: [
                const Text('🐱', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('弗糯糯', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.deepPurple.shade400, borderRadius: BorderRadius.circular(10)),
                      child: Text(_levelName(s.totalInteractions), style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(moodEmoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 4),
                    Text('${_stageName(s.totalInteractions)} · 陪伴第 ${(s.totalInteractions / 3).ceil()} 天',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: 运行 flutter analyze**

```bash
flutter analyze lib/widgets/pet_hero_card.dart
```
预期：零错误

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/pet_hero_card.dart
git commit -m "feat: PetHeroCard — 宠物头像+名字+等级+心情

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task A3: PetStatusBars — 2×2 进度条

**Files:**
- Create: `lib/widgets/pet_status_bars.dart`

- [ ] **Step 1: 创建 PetStatusBars**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pet/pet_controller.dart';

class PetStatusBars extends StatelessWidget {
  const PetStatusBars({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PetController>(
      builder: (context, ctrl, _) {
        final s = ctrl.state;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Row(children: [
                _Bar(emoji: '🍖', label: '饥饿', value: s.hunger, color: const Color(0xFF4ECCA3)),
                const SizedBox(width: 8),
                _Bar(emoji: '😊', label: '心情', value: s.mood.toInt(), color: const Color(0xFFE94560)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                _Bar(emoji: '⚡', label: '体力', value: s.energy, color: const Color(0xFFFFC107)),
                const SizedBox(width: 8),
                _Bar(emoji: '❤️', label: '好感', value: (s.affection / 10).clamp(0, 100).toInt(), color: const Color(0xFFFF6B9D)),
              ]),
            ],
          ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  final String emoji, label;
  final int value;
  final Color color;
  const _Bar({required this.emoji, required this.label, required this.value, required this.color});

  String get _text => value > 60 ? '充足' : value > 30 ? '一般' : '不足';

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 12)),
                const Spacer(),
                Text(_text, style: TextStyle(fontSize: 11, color: color)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: value / 100,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade800,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 运行 flutter analyze**

```bash
flutter analyze lib/widgets/pet_status_bars.dart
```
预期：零错误

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/pet_status_bars.dart
git commit -m "feat: PetStatusBars — 2×2 进度条网格 (饥饿/心情/体力/好感)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task A4: PetActionBar — 操作按钮行

**Files:**
- Create: `lib/widgets/pet_action_bar.dart`

- [ ] **Step 1: 创建 PetActionBar**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pet/pet_controller.dart';

class PetActionBar extends StatelessWidget {
  const PetActionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<PetController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Btn(icon: '🍖', label: '喂食', onTap: ctrl.feed),
          _Btn(icon: '🎾', label: '玩耍', onTap: ctrl.play),
          _Btn(icon: '💤', label: '哄睡', onTap: () => ctrl.sleep()),
          _Btn(icon: '💬', label: '聊天', onTap: () {}), // 由父组件切换标签
          _Btn(icon: '✋', label: '摸摸', onTap: ctrl.pet),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final String icon, label;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 运行 flutter analyze**

```bash
flutter analyze lib/widgets/pet_action_bar.dart
```
预期：零错误

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/pet_action_bar.dart
git commit -m "feat: PetActionBar — 5 操作按钮 (喂食/玩耍/哄睡/聊天/摸摸)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task A5: PetInfoChips — Token/统计 chips

**Files:**
- Create: `lib/widgets/pet_info_chips.dart`

- [ ] **Step 1: 创建 PetInfoChips**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/pet_token_service.dart';

class PetInfoChips extends StatelessWidget {
  const PetInfoChips({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PetTokenService>(
      builder: (context, svc, _) {
        final today = svc.todayTokens;
        final budget = svc.dailyBudget ?? 50000;
        final remaining = (budget - today).clamp(0, budget);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _Chip(label: '💰 $today / ${(budget / 1000).round()}k Token'),
              _Chip(label: '剩余 ${(remaining / 1000).round()}k'),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}
```

- [ ] **Step 2: 运行 flutter analyze**

```bash
flutter analyze lib/widgets/pet_info_chips.dart
```
预期：零错误

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/pet_info_chips.dart
git commit -m "feat: PetInfoChips — Token 用量 chip 行 (Consumer<PetTokenService>)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task A6: 重构 PetCenterScreen

**Files:**
- Modify: `lib/screens/pet_center_screen.dart`

- [ ] **Step 1: 用新组件替换旧的 _StatusCard / _TokenDashboard**

用以下完整代码替换 `pet_center_screen.dart`：

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/pet_hero_card.dart';
import '../widgets/pet_status_bars.dart';
import '../widgets/pet_action_bar.dart';
import '../widgets/pet_info_chips.dart';
import '../pet/pet_controller.dart';
import 'pet_chat_screen.dart';
import 'pet_memory_screen.dart';
import 'pet_diary_screen.dart';
import 'pet_settings_screen.dart';

class PetCenterScreen extends StatefulWidget {
  const PetCenterScreen({super.key});

  @override
  State<PetCenterScreen> createState() => _PetCenterScreenState();
}

class _PetCenterScreenState extends State<PetCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _switchToChat() => _tabController.animateTo(0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🐾 宠物中心'), centerTitle: true),
      body: Column(
        children: [
          const PetHeroCard(),
          const PetStatusBars(),
          PetActionBar(onChat: _switchToChat),
          const PetInfoChips(),
          const SizedBox(height: 4),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '💬 聊天'),
              Tab(text: '🧠 记忆'),
              Tab(text: '📖 日记'),
              Tab(text: '⚙️ 设置'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                PetChatScreen(),
                PetMemoryScreen(),
                PetDiaryScreen(),
                PetSettingsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

⚠ 注意：`PetActionBar` 接口更新为接受 `onChat` 回调，需要同步修改 Task A4 的代码。

- [ ] **Step 2: 更新 PetActionBar 接受 onChat 回调**

将 `PetActionBar` 的构造函数改为：
```dart
class PetActionBar extends StatelessWidget {
  final VoidCallback? onChat;
  const PetActionBar({super.key, this.onChat});
  // ... build 中聊天按钮用 onChat ?? () {}
}
```

- [ ] **Step 3: 运行 flutter analyze + test**

```bash
flutter analyze lib/screens/pet_center_screen.dart
flutter test
```
预期：零新增错误，289 测试通过

- [ ] **Step 4: Commit**

```bash
git add lib/screens/pet_center_screen.dart lib/widgets/pet_action_bar.dart
git commit -m "refactor: PetCenterScreen 用新组件替换 Hive 直读

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## 子项目 B：首页拆分重构

### Task B1: HomeWelcome — 空状态欢迎页

**Files:**
- Create: `lib/widgets/home_welcome.dart`

- [ ] **Step 1: 从 home_screen.dart 提取 _Welcome 组件**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';

class HomeWelcome extends StatelessWidget {
  final void Function(String prompt) onTap;

  const HomeWelcome({super.key, required this.onTap});

  static const _suggestions = [
    ('📊', '排序算法', '用通俗易懂的方式解释快速排序和归并排序'),
    ('📝', '商务邮件', '写一封正式的英文商务邮件确认会议'),
    ('📚', '小说推荐', '推荐几本好看的科幻小说并说明推荐理由'),
    ('🌌', '相对论', '用简单的方式解释相对论'),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('开始新对话', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('选择一个话题开始，或直接输入你的问题', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            ..._suggestions.map((s) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Text(s.$1, style: const TextStyle(fontSize: 24)),
                title: Text(s.$2),
                subtitle: Text(s.$3, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => onTap(s.$3),
              ),
            )),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 运行 flutter analyze**

```bash
flutter analyze lib/widgets/home_welcome.dart
```
预期：零错误

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/home_welcome.dart
git commit -m "refactor: HomeWelcome — 提取空状态欢迎页为独立组件

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task B2: HomeModelSelector — 模型选择 BottomSheet

**Files:**
- Create: `lib/widgets/home_model_selector.dart`

- [ ] **Step 1: 创建 HomeModelSelector**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../models/model_config.dart';

class HomeModelSelector extends StatelessWidget {
  final String currentModelId;
  final void Function(String modelId) onSelect;

  const HomeModelSelector({super.key, required this.currentModelId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        final models = ModelConfig.builtIn;
        final providers = ModelConfig.providers;
        final expanded = <String>{};
        return StatefulBuilder(
          builder: (context, setSt) => Column(
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
              ),
              Text('选择模型', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(controller: scrollController, children: [
                  for (final pid in ModelConfig.providerOrder)
                    if (providers.containsKey(pid))
                      Column(children: [
                        ListTile(
                          title: Text(providers[pid]!.name),
                          subtitle: Text(providers[pid]!.baseUrl),
                          trailing: Icon(expanded.contains(pid) ? Icons.expand_less : Icons.expand_more),
                          onTap: () => setSt(() => expanded.contains(pid) ? expanded.remove(pid) : expanded.add(pid)),
                        ),
                        if (expanded.contains(pid))
                          ...models.where((m) => m.provider == pid).map((m) => RadioListTile<String>(
                            title: Text(m.name),
                            subtitle: Text(m.id),
                            value: m.id,
                            groupValue: currentModelId,
                            onChanged: (v) { if (v != null) { onSelect(v); Navigator.pop(context); } },
                          )),
                      ]),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: flutter analyze**

```bash
flutter analyze lib/widgets/home_model_selector.dart
```

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/home_model_selector.dart
git commit -m "refactor: HomeModelSelector — 提取模型选择 BottomSheet

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task B3: HomeSearchSheet — 对话内搜索

**Files:**
- Create: `lib/widgets/home_search_sheet.dart`

- [ ] **Step 1: 创建 HomeSearchSheet**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/conversation_service.dart';

class HomeSearchSheet extends StatefulWidget {
  final ScrollController scrollController;
  final void Function(int index) onJump;

  const HomeSearchSheet({super.key, required this.scrollController, required this.onJump});

  @override
  State<HomeSearchSheet> createState() => _HomeSearchSheetState();
}

class _HomeSearchSheetState extends State<HomeSearchSheet> {
  final _ctrl = TextEditingController();
  List<int> _results = [];

  void _search(String q) {
    if (q.length < 2) { setState(() => _results = []); return; }
    final svc = context.read<ConversationService>();
    final msgs = svc.currentConversation?.messages ?? [];
    final indices = <int>[];
    for (int i = 0; i < msgs.length; i++) {
      if (msgs[i].content.toLowerCase().contains(q.toLowerCase())) indices.add(i);
    }
    setState(() => _results = indices);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '搜索对话内容...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _ctrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _ctrl.clear(); _search(''); }) : null,
            ),
            onChanged: _search,
          ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('找到 ${_results.length} 条匹配'),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  leading: Text('${_results[i] + 1}'),
                  title: Text(context.read<ConversationService>().currentConversation!.messages[_results[i]].content, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => widget.onJump(_results[i]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: flutter analyze**

```bash
flutter analyze lib/widgets/home_search_sheet.dart
```

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/home_search_sheet.dart
git commit -m "refactor: HomeSearchSheet — 提取对话内搜索为独立组件

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task B4: HomeMessageMenu — 消息长按菜单

**Files:**
- Create: `lib/widgets/home_message_menu.dart`

- [ ] **Step 1: 创建 HomeMessageMenu**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';

class HomeMessageMenu extends StatelessWidget {
  final bool isUser;
  final bool isLastAi;
  final VoidCallback onCopy;
  final VoidCallback onRegenerate;
  final VoidCallback? onDislike;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const HomeMessageMenu({
    super.key,
    required this.isUser,
    required this.isLastAi,
    required this.onCopy,
    required this.onRegenerate,
    this.onDislike,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('消息操作'),
      children: [
        _item(Icons.copy, '复制', onCopy),
        if (isLastAi && !isUser) _item(Icons.refresh, '重新生成', onRegenerate),
        if (isLastAi && !isUser && onDislike != null) _item(Icons.thumb_down, '踩', onDislike!),
        if (isUser && onEdit != null) _item(Icons.edit, '编辑', onEdit!),
        if (onDelete != null) _item(Icons.delete, '删除', onDelete!),
      ],
    );
  }

  Widget _item(IconData icon, String label, VoidCallback onTap) {
    return SimpleDialogOption(
      onPressed: onTap,
      child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)]),
    );
  }
}
```

- [ ] **Step 2: flutter analyze + test**

```bash
flutter analyze lib/widgets/home_message_menu.dart
flutter test
```

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/home_message_menu.dart
git commit -m "refactor: HomeMessageMenu — 提取消息长按菜单为独立组件

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task B5: HomeDrawer — 抽屉组件

**Files:**
- Create: `lib/widgets/home_drawer.dart`

- [ ] **Step 1: 创建 HomeDrawer**

这个文件从 home_screen.dart 提取 `_Drawer` (约 340 行)。由于篇幅限制，核心结构：

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/conversation_service.dart';
import '../services/persona_service.dart';
import '../services/pet_chat_service.dart';

class HomeDrawer extends StatefulWidget {
  final VoidCallback onNewConversation;
  final void Function(int index) onSelectConversation;
  final void Function(String id) onRename;
  final void Function(String id) onDelete;
  final void Function(String id, String format) onExport;

  const HomeDrawer({
    super.key,
    required this.onNewConversation,
    required this.onSelectConversation,
    required this.onRename,
    required this.onDelete,
    required this.onExport,
  });

  @override
  State<HomeDrawer> createState() => _HomeDrawerState();
}

class _HomeDrawerState extends State<HomeDrawer> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final _selected = <String>{};

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationService>(
      builder: (context, svc, _) {
        final conversations = svc.conversations;
        final filtered = _query.isEmpty
            ? conversations
            : conversations.where((c) => c.title.contains(_query) || c.messages.any((m) => m.content.contains(_query))).toList();

        return Drawer(
          child: SafeArea(
            child: Column(
              children: [
                // 品牌区
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    const Text('AI Chat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton.icon(icon: const Icon(Icons.bolt, size: 18), label: const Text('分享给糯糯'), onPressed: () => _shareToPet(svc)),
                  ]),
                ),
                // 人物角色切换
                Consumer<PersonaService>(
                  builder: (context, ps, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Text('人格: ${ps.currentPersonaName}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const Spacer(),
                      TextButton(onPressed: () { Navigator.pop(context); /* 跳转人格管理 */ }, child: const Text('管理')),
                    ]),
                  ),
                ),
                // 新对话 + 搜索
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    ElevatedButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('新对话'), onPressed: widget.onNewConversation),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _searchCtrl, decoration: const InputDecoration(hintText: '搜索对话...', prefixIcon: Icon(Icons.search, size: 18), isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)), onChanged: (v) => setState(() => _query = v))),
                  ]),
                ),
                // 对话列表
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text(filtered[i].title),
                      subtitle: Text(filtered[i].messages.lastOrNull?.content ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () { Navigator.pop(context); widget.onSelectConversation(i); },
                      onLongPress: () => _showConversationMenu(filtered[i].id),
                    ),
                  ),
                ),
                // 底部导航
                const Divider(height: 1),
                _navItem(Icons.auto_awesome, '人物角色', '/persona'),
                _navItem(Icons.feedback, '反馈知识库', '/feedback'),
                _navItem(Icons.pets, '弗糯糯', '/pet'),
                _navItem(Icons.settings, '设置', '/settings'),
              ],
            ),
          ),
        );
      },
    );
  }

  void _shareToPet(ConversationService svc) {
    if (_selected.isEmpty) return;
    final msgs = <String>[];
    for (final c in svc.conversations) {
      if (_selected.contains(c.id)) {
        for (final m in c.messages) msgs.add(m.content);
      }
    }
    context.read<PetChatService>().importMemories(msgs);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已分享给糯糯！')));
  }

  Future<void> _showConversationMenu(String id) async { /* 重命名/导出/删除 */ }

  Widget _navItem(IconData icon, String label, String route) {
    return ListTile(leading: Icon(icon, size: 20), title: Text(label, style: const TextStyle(fontSize: 14)), dense: true, onTap: () { Navigator.pop(context); Navigator.pushNamed(context, route); });
  }
}
```

- [ ] **Step 2: flutter analyze**

```bash
flutter analyze lib/widgets/home_drawer.dart
```

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/home_drawer.dart
git commit -m "refactor: HomeDrawer — 提取抽屉为独立组件

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task B6: HomeChatView + 更新 HomeScreen

**Files:**
- Create: `lib/widgets/home_chat_view.dart`
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: 创建 HomeChatView**

从 home_screen.dart 的 `_ChatView` 提取消息列表 + 横幅 + 滚动逻辑。核心接口：

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/conversation_service.dart';
import '../services/feedback_service.dart';
import '../services/memory_service.dart';
import 'home_message_menu.dart';

class HomeChatView extends StatefulWidget {
  final ScrollController scrollController;
  final VoidCallback? onMemoryPrompt;
  final void Function(int index) onJumpToIndex;

  const HomeChatView({
    super.key,
    required this.scrollController,
    this.onMemoryPrompt,
    required this.onJumpToIndex,
  });

  @override
  State<HomeChatView> createState() => _HomeChatViewState();
}

class _HomeChatViewState extends State<HomeChatView> with WidgetsBindingObserver {
  bool _showMemoryBanner = false;
  bool _showFeedbackBanner = false;
  bool _memoryPromptShown = false;
  bool _feedbackBannerShown = false;
  static const _memoryThreshold = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _showMessageMenu(int index) {
    final svc = context.read<ConversationService>();
    final msgs = svc.currentConversation?.messages ?? [];
    if (index < 0 || index >= msgs.length) return;
    final msg = msgs[index];
    showDialog(
      context: context,
      builder: (_) => HomeMessageMenu(
        isUser: msg.isUser,
        isLastAi: index == msgs.length - 1 && !msg.isUser,
        onCopy: () { /* copy */ Navigator.pop(context); },
        onRegenerate: () { /* regenerate */ Navigator.pop(context); },
        onDislike: () { /* dislike dialog */ Navigator.pop(context); },
        onEdit: msg.isUser ? () { /* edit dialog */ Navigator.pop(context); } : null,
        onDelete: () { /* delete confirm */ Navigator.pop(context); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationService>(
      builder: (context, svc, _) {
        final msgs = svc.currentConversation?.messages ?? [];
        return Column(children: [
          // 反馈横幅
          if (_showFeedbackBanner)
            Consumer<FeedbackService>(builder: (_, fb, __) => MaterialBanner(
              content: Text(fb.lastAdjustmentText ?? ''),
              leading: const Icon(Icons.lightbulb),
              actions: [TextButton(onPressed: () => setState(() => _showFeedbackBanner = false), child: const Text('知道了'))],
            )),
          // 记忆横幅
          if (_showMemoryBanner)
            MaterialBanner(
              content: const Text('对话够长了，要提取记忆吗？'),
              leading: const Icon(Icons.psychology),
              actions: [
                TextButton(onPressed: () { setState(() => _showMemoryBanner = false); widget.onMemoryPrompt?.call(); }, child: const Text('提取')),
                TextButton(onPressed: () => setState(() => _showMemoryBanner = false), child: const Text('忽略')),
              ],
            ),
          // 消息列表
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              itemCount: msgs.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(msgs[i].content),
                onLongPress: () => _showMessageMenu(i),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
```

⚠ 注意：这是简化版本。实际实现需完整迁移 home_screen.dart `_ChatView` 的所有逻辑。

- [ ] **Step 2: 更新 home_screen.dart 引用新组件**

在 home_screen.dart 中：
- 删除 `_Welcome`、`_ChatView`、`_Drawer`、`_showModelSelector`、`_showSearch`、`_showMessageMenu` 等私有类/方法
- 改为 import 并使用 `HomeWelcome`、`HomeDrawer`、`HomeChatView`、`HomeModelSelector`、`HomeSearchSheet`

- [ ] **Step 3: flutter analyze + test**

```bash
flutter analyze lib/screens/home_screen.dart
flutter test
```

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/home_chat_view.dart lib/screens/home_screen.dart
git commit -m "refactor: HomeChatView + HomeScreen 拆分重构

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## 子项目 C：设置页拆分

### Task C1-C6: 设置 Section 组件

由于每个 Section 结构类似，合并为 2 个 Task。

### Task C1: 创建 3 个基础 Section

**Files:**
- Create: `lib/widgets/settings_enable_section.dart`
- Create: `lib/widgets/settings_appearance_section.dart`
- Create: `lib/widgets/settings_persona_section.dart`

- [ ] **Step 1: 创建 SettingsEnableSection**

从 pet_settings_screen.dart 提取"启用开关 + AI 频率 + 触发场景"：

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../models/pet_config.dart';

class SettingsEnableSection extends StatelessWidget {
  final bool enabled;
  final AiFrequency frequency;
  final Set<TriggerScene> scenes;
  final ValueChanged<bool> onToggle;
  final ValueChanged<AiFrequency> onFrequencyChanged;
  final ValueChanged<Set<TriggerScene>> onScenesChanged;

  const SettingsEnableSection({
    super.key,
    required this.enabled,
    required this.frequency,
    required this.scenes,
    required this.onToggle,
    required this.onFrequencyChanged,
    required this.onScenesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(title: const Text('启用悬浮宠物'), value: enabled, onChanged: onToggle),
      if (enabled) ...[
        const Padding(padding: EdgeInsets.only(left: 16), child: Text('AI 主动建议频率', style: TextStyle(fontWeight: FontWeight.w500))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<AiFrequency>(
            segments: const [
              ButtonSegment(value: AiFrequency.silent, label: Text('安静')),
              ButtonSegment(value: AiFrequency.occasional, label: Text('偶尔')),
              ButtonSegment(value: AiFrequency.chatty, label: Text('话多')),
            ],
            selected: {frequency},
            onSelectionChanged: (v) => onFrequencyChanged(v.first),
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 16), child: Text('触发场景', style: TextStyle(fontWeight: FontWeight.w500))),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, children: TriggerScene.values.map((s) => FilterChip(
            label: Text(s.label),
            selected: scenes.contains(s),
            onSelected: (v) {
              final updated = Set<TriggerScene>.from(scenes);
              v ? updated.add(s) : updated.remove(s);
              onScenesChanged(updated);
            },
          )).toList()),
        ),
      ],
    ]);
  }
}
```

- [ ] **Step 2: 创建 SettingsAppearanceSection**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';

class SettingsAppearanceSection extends StatelessWidget {
  final String skinName;
  final double scale;
  final VoidCallback? onSkinTap;
  final ValueChanged<double> onScaleChanged;

  const SettingsAppearanceSection({
    super.key,
    required this.skinName,
    required this.scale,
    this.onSkinTap,
    required this.onScaleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(title: const Text('皮肤'), subtitle: Text(skinName), trailing: const Icon(Icons.chevron_right), onTap: onSkinTap ?? () {}),
      const Divider(height: 1),
      Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('宠物大小: ${scale.toStringAsFixed(1)}x', style: const TextStyle(fontWeight: FontWeight.w500)),
        Slider(value: scale, min: 0.5, max: 1.5, divisions: 10, label: '${scale.toStringAsFixed(1)}x', onChanged: onScaleChanged),
      ])),
    ]);
  }
}
```

- [ ] **Step 3: 创建 SettingsPersonaSection**

从 pet_settings_screen.dart 提取性格设置（模板下拉 + Prompt 编辑）。

- [ ] **Step 4: flutter analyze**

```bash
flutter analyze lib/widgets/settings_enable_section.dart lib/widgets/settings_appearance_section.dart lib/widgets/settings_persona_section.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/settings_enable_section.dart lib/widgets/settings_appearance_section.dart lib/widgets/settings_persona_section.dart
git commit -m "refactor: 设置 Section — 启用/外观/性格

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task C2: 创建剩余 3 个 Section + 更新 PetSettingsScreen

**Files:**
- Create: `lib/widgets/settings_model_section.dart`
- Create: `lib/widgets/settings_token_section.dart`
- Create: `lib/widgets/settings_debug_section.dart`
- Modify: `lib/screens/pet_settings_screen.dart`

- [ ] **Step 1: 创建 SettingsModelSection (~100 行)**

从 pet_settings_screen.dart 提取模型配置（主模型下拉 + 视觉开关 + 视觉模型选择 + API Key）。

- [ ] **Step 2: 创建 SettingsTokenSection (~50 行)**

预算快捷选择 + 自定义输入 + 防抖保存。

- [ ] **Step 3: 创建 SettingsDebugSection (~60 行)**

日志复制/导出/共享/清空。

- [ ] **Step 4: 更新 pet_settings_screen.dart**

将所有 `_buildXxxSection()` 方法替换为对应的 Section Widget import 和使用。原 688 行缩减到 ~80 行（组装 ListView）。

- [ ] **Step 5: flutter analyze + test**

```bash
flutter analyze lib/screens/pet_settings_screen.dart
flutter test
```
预期：零新增错误，289 全部通过

- [ ] **Step 6: 最终 Commit**

```bash
git add lib/widgets/ lib/screens/pet_settings_screen.dart lib/screens/home_screen.dart lib/screens/pet_center_screen.dart
git commit -m "refactor: Phase 1 优化完成 — 宠物中心+首页+设置拆分为 19 个组件

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## 验证清单

| # | 检查项 | 命令 |
|---|--------|------|
| 1 | 全量测试通过 | `flutter test` |
| 2 | 零新增分析错误 | `flutter analyze` |
| 3 | APK 构建成功 | `cd android && ./gradlew :app:assembleDebug` |
| 4 | 宠物中心页面正常渲染 | 手动验证 |
| 5 | 首页正常渲染（抽屉/聊天/搜索） | 手动验证 |
| 6 | 设置页正常渲染（所有 Section） | 手动验证 |

---

## 风险与回滚

- **风险:** 组件拆分后 import 路径错误 → 通过 `flutter analyze` 检查
- **风险:** HomeScreen 拆分丢功能 → 逐个组件提取，每个 Task 后跑测试
- **回滚:** 改动全部在 `lib/widgets/` 和 3 个 screen 文件，git revert 即可
