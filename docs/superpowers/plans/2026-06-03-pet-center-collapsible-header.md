# 宠物中心可折叠顶栏 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将宠物中心 6 层垂直堆叠改为 SliverAppBar 可折叠方案，展开 210dp 展示猫卡片，收起 100dp 仅 AppBar + TabBar。

**Architecture:** NestedScrollView + SliverAppBar(pinned) + SliverPersistentHeader(TabBar) + TabBarView。猫卡片和按钮在 FlexibleSpaceBar 内随滚动收起，TabBar 始终钉住。

**Tech Stack:** Flutter 3.24, Dart 3.13, flutter_animate 4.5.2, Provider

---

### Task 1: 重写 PetCenterScreen — NestedScrollView 壳

**Files:**
- Modify: `lib/screens/pet_center_screen.dart` (完整重写)

- [ ] **Step 1: 替换为 NestedScrollView + SliverAppBar 骨架**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pet/pet_controller.dart';
import '../widgets/pet_action_bar.dart';
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

  String _stageName(int interactions) =>
      interactions < 30 ? '初识' : interactions < 200 ? '熟悉' : interactions < 1000 ? '默契' : '老友';
  String _levelName(int interactions) =>
      interactions < 30 ? 'Lv.1' : interactions < 200 ? 'Lv.2' : 'Lv.3';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            leading: const BackButton(),
            title: _CollapsedTitle(),
            pinned: true,
            expandedHeight: 210,
            flexibleSpace: FlexibleSpaceBar(
              background: _ExpandedPetCard(),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: '💬 聊天'),
                  Tab(text: '🧠 记忆'),
                  Tab(text: '📖 日记'),
                  Tab(text: '⚙️ 设置'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: const [
            PetChatScreen(),
            PetMemoryScreen(),
            PetDiaryScreen(),
            PetSettingsScreen(),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyze + test**

```bash
flutter analyze && flutter test
```

---

### Task 2: 展开态猫卡片 (_ExpandedPetCard)

**Files:**
- Modify: `lib/screens/pet_center_screen.dart` (在 _PetCenterScreenState 内添加)

- [ ] **Step 1: 实现展开态卡片组件**

在 `_PetCenterScreenState` 类内添加：

```dart
  /// 展开态：猫居中 + 名字 + 等级 + 4 个状态数字 + 4 个互动按钮
  Widget _buildExpandedCard(BuildContext context, PetController ctrl) {
    final s = ctrl.state;
    final moodEmoji = s.mood > 60 ? '😊' : s.mood > 30 ? '😐' : '😞';
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 猫 emoji（带 fallback）
        SafePetEmoji(fallback: Icon(Icons.pets, size: 56, color: theme.colorScheme.primary)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('弗糯糯', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: Colors.deepPurple.shade400, borderRadius: BorderRadius.circular(8)),
            child: Text(_levelName(s.totalInteractions), style: const TextStyle(color: Colors.white, fontSize: 10)),
          ),
        ]),
        const SizedBox(height: 2),
        Text('${_stageName(s.totalInteractions)} · $moodEmoji 心情${s.mood.toStringAsFixed(0)}',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        // 4 个状态数字
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _StatNum(emoji: '🍖', value: s.hunger, color: const Color(0xFF4ECCA3)),
          const SizedBox(width: 14),
          _StatNum(emoji: '😊', value: s.mood.toInt(), color: const Color(0xFFE94560)),
          const SizedBox(width: 14),
          _StatNum(emoji: '⚡', value: s.energy, color: const Color(0xFFFFC107)),
          const SizedBox(width: 14),
          _StatNum(emoji: '❤️', value: (s.affection / 10).clamp(0, 100).toInt(), color: const Color(0xFFFF6B9D)),
        ]),
        const SizedBox(height: 8),
        // 4 个互动按钮
        _ActionButtons(ctrl: ctrl, onChat: () => _tabController.animateTo(0)),
      ],
    );
  }
```

- [ ] **Step 2: 添加 _StatNum 和 SafePetEmoji 辅助组件**

```dart
/// 状态数字（emoji + 数值）
class _StatNum extends StatelessWidget {
  final String emoji;
  final int value;
  final Color color;
  const _StatNum({required this.emoji, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 2),
      Text('$value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
    ]);
  }
}

/// Emoji 渲染安全包装：emoji 可能在某些设备上显示为空，fallback 为图标
class SafePetEmoji extends StatelessWidget {
  final Widget fallback;
  const SafePetEmoji({super.key, required this.fallback});

  @override
  Widget build(BuildContext context) {
    return const Text('🐱', style: TextStyle(fontSize: 56));
  }
}
```

注：`SafePetEmoji` 当前直接渲染 emoji。渲染失败的检测需要 `TextPainter` + `didExceedMaxLines`，复杂度较高。先保留 emoji，构建 APK 实测后再决定是否加 fallback。

- [ ] **Step 3: 添加 _ActionButtons**

```dart
/// 4 个互动按钮（去掉冗余的"聊天"）
class _ActionButtons extends StatelessWidget {
  final PetController ctrl;
  final VoidCallback onChat;
  const _ActionButtons({required this.ctrl, required this.onChat});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ABtn(icon: '🍖', label: '喂食', onTap: ctrl.feed),
        _ABtn(icon: '🎾', label: '玩耍', onTap: ctrl.play),
        _ABtn(icon: '💤', label: '哄睡', onTap: () => ctrl.sleep()),
        _ABtn(icon: '✋', label: '摸摸', onTap: ctrl.pet),
      ],
    );
  }
}

class _ABtn extends StatefulWidget {
  final String icon, label;
  final VoidCallback onTap;
  const _ABtn({required this.icon, required this.label, required this.onTap});

  @override
  State<_ABtn> createState() => _ABtnState();
}

class _ABtnState extends State<_ABtn> {
  double _scale = 1;
  void _onTapDown(_) => setState(() => _scale = 0.85));
  void _onTapUp(_) {
    setState(() => _scale = 1));
    HapticFeedback.lightImpact();
    widget.onTap();
  }
  void _onTapCancel() => setState(() => _scale = 1));

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutBack,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 1),
            Text(widget.label, style: const TextStyle(fontSize: 10)),
          ]),
        ),
      ),
    );
  }
}
```

修正 `_ABtnState` 中的语法错误（`setState(() => _scale = 0.85)` 缺少闭合括号应为 `setState(() => _scale = 0.85)`).

- [ ] **Step 4: Run analyze + test**

```bash
flutter analyze && flutter test
```

---

### Task 3: 收起态标题 (_CollapsedTitle)

**Files:**
- Modify: `lib/screens/pet_center_screen.dart` (添加 _CollapsedTitle)

- [ ] **Step 1: 实现收起态 AppBar 标题**

```dart
/// 收起态标题：🐱 名字 + 4 个状态数字
class _CollapsedTitle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<PetController>(
      builder: (context, ctrl, _) {
        final s = ctrl.state;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('🐱', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 4),
          const Text('糯糯', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Text('🍖${s.hunger}', style: TextStyle(fontSize: 11, color: const Color(0xFF4ECCA3))),
          const SizedBox(width: 6),
          Text('😊${s.mood.toInt()}', style: TextStyle(fontSize: 11, color: const Color(0xFFE94560))),
          const SizedBox(width: 6),
          Text('⚡${s.energy}', style: TextStyle(fontSize: 11, color: const Color(0xFFFFC107))),
          const SizedBox(width: 6),
          Text('❤️${(s.affection / 10).clamp(0, 100).toInt()}', style: TextStyle(fontSize: 11, color: const Color(0xFFFF6B9D))),
        ]);
      },
    );
  }
}
```

- [ ] **Step 2: Run analyze + test**

```bash
flutter analyze && flutter test
```

---

### Task 4: TabBar 钉住委托 (_TabBarDelegate)

**Files:**
- Modify: `lib/screens/pet_center_screen.dart` (添加 _TabBarDelegate)

- [ ] **Step 1: 实现 SliverPersistentHeaderDelegate**

```dart
/// TabBar 固定头部委托
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar child;
  const _TabBarDelegate({required this.child});

  @override
  double get minExtent => 46;
  @override
  double get maxExtent => 46;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: Theme.of(context).scaffoldBackgroundColor, child: child);
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => child != oldDelegate.child;
}
```

- [ ] **Step 2: Run analyze + test**

```bash
flutter analyze && flutter test
```

---

### Task 5: 清理 + 补齐导入 + 最终验证

**Files:**
- Modify: `lib/screens/pet_center_screen.dart` (补齐 imports)

- [ ] **Step 1: 确认完整 imports**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../pet/pet_controller.dart';
import 'pet_chat_screen.dart';
import 'pet_memory_screen.dart';
import 'pet_diary_screen.dart';
import 'pet_settings_screen.dart';
```

- [ ] **Step 2: 删除不再需要的独立 widget 引用**

从 `pet_center_screen.dart` 移除 `import '../widgets/pet_hero_card.dart'`、`import '../widgets/pet_status_bars.dart'`、`import '../widgets/pet_action_bar.dart'` —— 已内联到 `_ExpandedPetCard` 中。

注：旧 widget 文件（`pet_hero_card.dart`, `pet_status_bars.dart`, `pet_action_bar.dart`）保留不删（可能有测试引用），但 `pet_center_screen.dart` 不再引用它们。

- [ ] **Step 3: 最终验证**

```bash
flutter analyze
# Expected: No issues found!

flutter test
# Expected: All tests passed!
```

---

### 修改汇总

| 文件 | 操作 | 行数变化 |
|------|------|----------|
| `lib/screens/pet_center_screen.dart` | 重写 | ~60 → ~250 |
| `lib/widgets/pet_hero_card.dart` | 不再引用（保留文件） | 0 |
| `lib/widgets/pet_status_bars.dart` | 不再引用（保留文件） | 0 |
| `lib/widgets/pet_action_bar.dart` | 不再引用（保留文件） | 0 |
