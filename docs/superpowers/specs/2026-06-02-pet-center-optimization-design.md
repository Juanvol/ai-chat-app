# 宠物中心 + 首页 + 设置 — Phase 1 优化 Spec

> **For agentic workers:** 使用 writing-plans skill 生成实施计划后执行。

**Goal:** 升级宠物中心为可互动的宠物管理中枢，拆分首页/设置页为大文件拆小组件的结构，全面接入 Provider 实时状态管理。

**Architecture:** 拆大文件为独立组件，Hive 直读改为 Consumer<Service> 监听，宠物中心新增操作按钮组 + 进度条可视化。

**Tech Stack:** Flutter 3.45 / Dart 3.13 / Provider / Hive

---

## 子项目 A：宠物中心 UI 升级

### 当前问题
- `pet_center_screen.dart` 257 行，`_StatusCard` 和 `_TokenDashboard` 直接读 Hive，不实时
- 无任何操作按钮，用户只能看不能互动
- 状态用纯文字展示（"饱了"/"有点饿"/"好饿"），不直观

### 目标
宠物卡片 + 5 操作按钮 + 4 进度条 + 3 chip + 标签栏，组件化拆分。

### 文件

| 文件 | 操作 | 职责 |
|------|------|------|
| `lib/widgets/pet_hero_card.dart` | 🆕 | 宠物头像、名字、等级、陪伴天数、心情 |
| `lib/widgets/pet_status_bars.dart` | 🆕 | 2×2 进度条网格：饥饿/心情/体力/好感，渐变色 |
| `lib/widgets/pet_action_bar.dart` | 🆕 | 5 个操作按钮（喂食/玩耍/哄睡/聊天/更多），Consumer<PetController> |
| `lib/widgets/pet_info_chips.dart` | 🆕 | Token/聊天次数/日记篇数 chip 行，Consumer<PetTokenService> |
| `lib/screens/pet_center_screen.dart` | 🔧 | 组装上述组件 + TabBar，~100 行 |
| `lib/pet/pet_controller.dart` | 🔧 | +pet() 摸摸方法，好感度 +5 |
| `lib/main.dart` | 🔧 | 注册 PetController 为 ChangeNotifierProvider |

### 数据流
```
PetController (ChangeNotifier)          PetTokenService (ChangeNotifier)
    │ notifyListeners()                      │ notifyListeners()
    ├── PetStatusBars (Consumer)             ├── PetInfoChips (Consumer)
    ├── PetActionBar (Consumer)              └── PetCenterScreen (Consumer)
    └── PetHeroCard (Consumer)
```

### 交互
1. 用户点击"喂食" → `ctrl.feed()` → hunger=100, status=eating, affection+10 → notify → UI 刷新 → 4 秒后自动 idle
2. 用户点击"玩耍" → `ctrl.play()` → status=happy, affection+20 → notify → UI 刷新 → 4 秒后自动 idle
3. 用户点击"哄睡" → `ctrl.sleep()` → status=sleeping → notify → UI 刷新
4. 用户点击"聊天" → 切换到聊天标签页
5. 用户点击"更多" → 弹出 BottomSheet 显示改名/换装/分享

### 进度条设计
```dart
// 每一条
Column(children: [
  Row(emoji + label, value),
  ClipRRect(borderRadius: 4, child: LinearProgressIndicator(value: v/100, color: gradient)),
  Text(decayNote, style: caption),
])
```
颜色映射：饥饿=#4ecca3 → #7eecc3 · 心情=#e94560 → #f07080 · 体力=#ffc107 → #ffd54f · 好感=#ff6b9d → #ff8fb3

---

## 子项目 B：首页拆分重构

### 当前问题
`home_screen.dart` 1057 行。抽屉、聊天视图、3 个 BottomSheet（搜索/人物角色/模型选择）、消息菜单、反馈/记忆横幅全在一个文件里。

### 目标
拆为 6 个独立文件，每个 100-200 行，职责单一。

### 文件

| 文件 | 操作 | 职责 |
|------|------|------|
| `lib/screens/home_screen.dart` | 🔧 | 顶层组装，Consumer<ConversationService>，~120 行 |
| `lib/widgets/home_drawer.dart` | 🆕 | 抽屉：品牌/人物角色切换/对话列表/多选/导航 |
| `lib/widgets/home_chat_view.dart` | 🆕 | 聊天消息列表 + 滚动控制 + 横幅 + 消息菜单 |
| `lib/widgets/home_welcome.dart` | 🆕 | 空状态欢迎页 + 4 个快速启动建议 |
| `lib/widgets/home_model_selector.dart` | 🆕 | 模型选择 BottomSheet：按提供商分组 + RadioTile |
| `lib/widgets/home_search_sheet.dart` | 🆕 | 对话内搜索 BottomSheet |
| `lib/widgets/home_message_menu.dart` | 🆕 | 消息长按菜单：复制/重新生成/踩/编辑/删除 |

### 拆分原则
- 每个文件只 export 一个顶层 Widget
- 依赖通过构造函数传入，不通过 context.read() 跨层获取
- 状态回调用 VoidCallback / ValueChanged 向上传递

---

## 子项目 C：设置页拆分

### 当前问题
`pet_settings_screen.dart` 688 行，12 个内联 build 方法。皮肤选择器是空占位。

### 目标
每个 Section 一个独立文件，保持与现有功能完全一致。

### 文件

| 文件 | 操作 | 职责 |
|------|------|------|
| `lib/screens/pet_settings_screen.dart` | 🔧 | 组装 ListView + Section 列表，~80 行 |
| `lib/widgets/settings_enable_section.dart` | 🆕 | 启用开关 + 频率 + 触发场景 |
| `lib/widgets/settings_appearance_section.dart` | 🆕 | 皮肤选择器 + 大小滑块 |
| `lib/widgets/settings_persona_section.dart` | 🆕 | 性格模板 + SystemPrompt 编辑 |
| `lib/widgets/settings_model_section.dart` | 🆕 | 主模型 + 视觉模型 + API Key |
| `lib/widgets/settings_token_section.dart` | 🆕 | 预算快捷选择 + 自定义输入 |
| `lib/widgets/settings_debug_section.dart` | 🆕 | 日志复制/导出/共享/清空 |

---

## 约束

- 不改变任何现有功能行为
- 中文 UI 字符串直接写
- import 用相对路径
- Consumer/context.watch 只在 build() 中调用
- 不新增外部依赖
- 皮肤选择器保持占位（"更多皮肤即将推出"）

## 测试

- 新组件添加 Widget 测试（渲染 + 交互）
- 现有 289 测试必须全部通过
- flutter analyze 零新增错误
