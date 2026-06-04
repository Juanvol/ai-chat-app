# 宠物中心可折叠顶栏 — 设计文档

> **状态:** 已批准 | **日期:** 2026-06-03

## 目标

将宠物中心 6 层垂直堆叠（410dp 头部）压缩为可折叠 SliverAppBar 方案，展开时 210dp 展示完整猫卡片，收起时 100dp 仅显示 AppBar + TabBar，Tab 内容空间从 250dp 提升至 580dp。

## 架构

**组件:** `NestedScrollView` + `SliverAppBar` + `SliverPersistentHeader`(TabBar) + `TabBarView`

**折叠策略:** `SliverAppBar` 的 `expandedHeight` 为 210dp，`pinned: true`。猫卡片和互动按钮放在 `FlexibleSpaceBar` 内，随滚动收起。TabBar 通过 `SliverPersistentHeader` 始终钉在顶部。

## 改动范围

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/screens/pet_center_screen.dart` | 重写 | NestedScrollView + SliverAppBar |
| `lib/widgets/pet_hero_card.dart` | 修改 | 拆分为展开版和收起版 |
| `lib/widgets/pet_action_bar.dart` | 修改 | 嵌入 FlexibleSpaceBar |
| `lib/widgets/pet_status_bars.dart` | 删除 | 状态数字直接写在卡内 |
| `lib/widgets/pet_info_chips.dart` | 删除引用 | PetCenterScreen 不再引用 |

## 展开态（刚进入 / 下滑到底）

```
┌─ AppBar: 🐾 宠物中心 (← 返回) ────┐  56dp
│                                    │
│            🐱 (56px)               │
│         弗糯糯  Lv.2               │  210dp
│       初识 · 😊 心情60             │  expandedHeight
│    🍖80    😊60    ⚡75    ❤️50    │
│                                    │
│   🍖喂食  🎾玩耍  💤哄睡  ✋摸摸   │
├────────────────────────────────────┤
│ 💬聊天 │ 🧠记忆 │ 📖日记 │ ⚙️设置  │  46dp pinned
├────────────────────────────────────┤
│          TabView 内容               │  剩余空间
```

## 收起态（上滑后）

```
┌─ ← 🐱糯糯  🍖80 😊60 ⚡75 ❤️50 ──┐  56dp pinned
├────────────────────────────────────┤
│ 💬聊天 │ 🧠记忆 │ 📖日记 │ ⚙️设置  │  46dp pinned
├────────────────────────────────────┤
│          TabView 内容 (~580dp)      │  几乎全屏
```

## 交互

- 进入宠物中心 → 展开态
- 上滑 Tab 内容 → FlexibleSpaceBar 收起，AppBar 标题切换为紧凑状态行
- 下滑到顶 → 重新展开，露出互动按钮
- 切 Tab → 保持折叠/展开状态

## emoji 显示安全

`Text('🐱')` 在部分国产 ROM 上可能渲染为空 → 包裹 `Text` 并在 `TextPainter` 检测到空渲染时 fallback 为 `Icon(Icons.pets, size: 56)`。

## 自我审查

- [x] 无 TBD/TODO
- [x] 架构与功能描述一致
- [x] 范围聚焦：仅宠物中心布局，不涉及其它页面
- [x] 无歧义需求
