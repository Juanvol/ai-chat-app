# 弗糯糯宠物增强 — 设计文档

> ⚠️ **本 Spec 已被 [2026-05-30-pet-agent-design.md](./2026-05-30-pet-agent-design.md) 取代。**
> 保留此文件作为 Phase 1 地基参考。Phase 0 地基（PetState/PetController/PetRenderer/PetWindow/MiniChat）已全部完成。
> 后续所有新功能开发请以 Agent Spec 为准。

> 基于 `2026-05-30-pet-design.md`，增强宠物感、对话系统和可定制性。

**目标**：让宠物从"反应式动画播放器"进化为"有性格、有记忆、会自主行动的活物"。

**技术栈**：Flutter 3.24 / Dart 3.5 / Provider / Hive / 双引擎架构

---

## 功能列表

| ID | 功能 | 优先级 |
|----|------|--------|
| F1 | 状态可视化（身体语言 + 表情气泡） | P0 |
| F2 | 自主行为（随机位移 + 镜像翻转） | P0 |
| F3 | 对话上下文记忆（最近 3 轮注入） | P1 |
| F4 | 独立对话体系（悬浮窗 + 全屏共享） | P1 |
| F5 | 交叉记忆（主 App 对话多选 → 宠物记忆） | P1 |
| F6 | 自定义性格（模板 + 自由文本 + 试聊预览） | P1 |
| F7 | 记忆管理（用户增删宠物记忆和导入记录） | P1 |
| F8 | 宠物中心统一入口（状态卡片 + 3 Tab） | P1 |
| F9 | 性格试聊预览 | P1 |
| F10 | 对话自动标题 + 用户可自定义修改 | P1 |

---

## UI 结构：宠物中心

```
主 App 抽屉
  └─ 「🐾 宠物中心」  ← 唯一入口（新增 PetCenterScreen）
       │
       ├─ 顶部  ┌─────────────────────────────────┐
       │       │  🐱 弗糯糯   好感度 ❤️❤️❤️ 320   │
       │       │  😊 开心  |  🍖 饱了  |  ⚡ 精神   │
       │       └─────────────────────────────────┘
       │
       ├─ Tab 1: 💬 聊天     → PetChatScreen
       ├─ Tab 2: 🧠 记忆     → PetMemoryScreen
       └─ Tab 3: ⚙️ 设置     → PetSettingsScreen
```

**状态卡片**：三个指标根据数值动态切换：
- 心情：😊开心 / 😐一般 / 😿难过
- 饱饿：🍖饱了 / 🦴有点饿 / 🍽️很饿
- 体力：⚡精神 / 😴困了 / 💤疲惫

**主 App 对话多选分享入口**：
- 对话列表右上角「📤」→ 选择模式
- 勾选多条对话 → 底部「分享给糯糯」按钮
- 批量调用 AI 摘要 → 每条对话独立生成一条记忆

---

## 架构

### 新建文件

| 文件 | 职责 |
|------|------|
| `lib/pet/pet_persona.dart` | 宠物性格数据模型 |
| `lib/services/pet_chat_service.dart` | 宠物对话 CRUD、上下文拼接、交叉记忆、记忆管理 |
| `lib/pet/pet_behavior.dart` | 自主行为 Timer（位移/翻转）+ 表情气泡叠加 |
| `lib/screens/pet_center_screen.dart` | 宠物中心：状态卡片 + TabBar（聊天/记忆/设置） |
| `lib/screens/pet_chat_screen.dart` | 主 App 全屏宠物聊天页 |
| `lib/screens/pet_memory_screen.dart` | 宠物记忆管理页（列表 + 增删 + 导入记录管理） |

### 修改文件

| 文件 | 改动 |
|------|------|
| `lib/pet/mini_chat.dart` | 对话持久化 + 上下文记忆注入 + 共享 PetChatService |
| `lib/pet/pet_window.dart` | 集成 PetBehavior + PetPersona |
| `lib/pet/pet_renderer.dart` | 状态可视化（表情图标叠加层） |
| `lib/services/pet_ai_service.dart` | 改读 PetPersona.systemPrompt 替代硬编码 |
| `lib/screens/pet_settings_screen.dart` | 性格编辑器（模板选择 + 自由文本 + 试聊预览） |
| `lib/screens/home_screen.dart` | 抽屉入口改为 PetCenter + 对话多选分享 |

---

## 模块设计

### 1. PetPersona（性格模型）

`lib/pet/pet_persona.dart`

```dart
class PetPersona {
  final String name;           // 宠物名，默认"弗糯糯"
  final String systemPrompt;   // 完整 system prompt（自由文本）
  final String templateId;     // 可选引用主 App Persona 模板 ID
  final String traits;         // 简短性格标签（如"傲娇、毒舌、粘人"）
}
```

- 存储：`pet_config` box，key `persona`
- PetAiService 读 `PetPersona.systemPrompt` 替代硬编码 `_personaPrompt`
- 模板列表**复用** PersonaService 的 `mbtiTemplates` 和 `emotionTemplates`
- 用户选模板后，`systemPrompt` 自动适配为宠物风格

**试聊预览（F9）**：
- 性格编辑页底部「试试聊天」按钮
- 弹出小对话框（2-3 轮对话）
- 用户发一句 → AI 用当前编辑的性格回复
- 满意 → 保存；不满意 → 继续调
- 试聊对话框顶部提示"当前为临时预览，未保存"

### 2. PetChatService（对话管理）

`lib/services/pet_chat_service.dart`

```
PetChatService extends ChangeNotifier
├── conversations      List<PetConversation>
├── currentId          String?
├─────────────────────────────────────────
├── createChat()       → 新建对话，自动标题
├── switchChat(id)     → 切换当前对话
├── deleteChat(id)     → 删除 + 切到最近一个
├── renameChat(id, title) → 用户自定义修改标题
├── addMessage(role, content) → 追加消息 + 自动生成标题
├── buildContext()     → 拼接上下文文本
├── importMemories(List<String> convIds) → 批量导入（多选）
├── listMemories()     → 列出所有宠物记忆
├── deleteMemory(id)   → 删除指定记忆
├── listImports()      → 列出所有导入的对话引用
├── removeImport(id)   → 移除导入关联 + 对应记忆
└── listChats()        → 获取对话列表
```

**对话标题自动生成 + 自定义修改（F10）**：
- 创建对话时标题为"新对话"
- 第一轮对话后，截取用户消息前 15 字作为标题
- 用户可在对话列表长按 → 重命名 → 输入自定义标题
- `renameChat(id, title)` 更新标题并持久化

**批量导入 `importMemories(List<String> convIds)`（F5 多选）**：
- 并行调用 LLM 提取摘要（每条独立，失败不影响其他）
- 返回成功条数
- 每条摘要同时写入 `pet_memories` 和主 App `memories`

### 3. PetBehavior（自主行为 + 状态可视化）

`lib/pet/pet_behavior.dart`

StatefulWidget，包裹 PetRenderer，功能：

**随机位移**：
- Timer 每 30~60 秒触发（随机间隔）
- delta ±20px，调用 MethodChannel `moveWindow`
- 闲聊中（`isChatting == true`）跳过位移

**随机镜像翻转**：
- `Transform.flip(flipX: bool)` 包裹 child
- 翻转时 200ms 过渡动画

**状态表情气泡（F1）**：
- 在 PetRenderer 上方叠加 emoji/短文本气泡
- 触发条件基于 `PetController.state`：
  - `hunger < 30` → 💧 "有点饿了喵..."
  - `energy < 20` → 💤 打哈欠
  - `mood > 80` → ✨ "今天好开心喵~"
  - `affection > 200` → 💕 "主人最好了喵~"
- 气泡出现 3 秒后消失，不持续遮挡
- 10 分钟内同类型气泡最多触发 1 次（防刷屏）

**ecoMode**：true 时暂停所有自主行为。

### 4. PetCenterScreen（统一入口）

`lib/screens/pet_center_screen.dart`

```
Scaffold
├── AppBar: "🐾 宠物中心"
├── body: Column
│   ├── PetStatusCard (F8)
│   │   ├── Row: 头像 + 名字 + 好感度数值
│   │   └── Row: 😊开心 | 🍖饱了 | ⚡精神
│   └── TabBar + TabBarView
│       ├── Tab 1: PetChatScreen
│       ├── Tab 2: PetMemoryScreen
│       └── Tab 3: PetSettingsScreen
```

**PetStatusCard**：独立 Widget，从 `PetController.state` 读取数据，实时刷新。

### 5. MiniChat 改造

- 对话持久化：`initState` 从 `PetChatService.currentId` 加载历史
- 上下文注入：`buildContext()` 拼入 system prompt
- 关闭时保存但不删除对话

### 6. PetChatScreen（全屏聊天）

- 对话列表（左滑删除、长按重命名、点击切换）
- 消息列表（暗色 UI，流式 AI 回复）
- 点赞/踩反馈

### 7. PetMemoryScreen（记忆管理）

- 列表：记忆内容 + 来源标签（聊天/截图/导入）
- 左滑删除任意记忆
- 导入记录列表：原对话标题 + 导入时间 → 可移除

### 8. PetSettingsScreen 改造

- 性格编辑器（模板选择 + 自由文本 + 试聊按钮）
- 原有设置（开关/频率/皮肤/比例/自动启动）

### 9. HomeScreen 改造

- 抽屉入口改为「🐾 宠物中心」
- 对话列表右上角「📤」→ 选择模式 → 底部「分享给糯糯」
- 调用 `PetChatService.importMemories(selectedIds)`

---

## 数据流

```
┌─ 引擎 #1 (主 App) ────────────────────────────────────┐
│                                                        │
│  HomeScreen                                            │
│  ├─ 多选对话 → importMemories([ids]) ──┐              │
│  └─ 抽屉 → PetCenterScreen ←──────────┤              │
│      ├─ PetStatusCard                  │              │
│      ├─ PetChatScreen ←───────────────┤              │
│      ├─ PetMemoryScreen ←─────────────┤              │
│      └─ PetSettingsScreen              │              │
│          └─ PetPersona                 │              │
│  PetChatService                        │              │
│  ├─ pet_chats box (读写)               │              │
│  ├─ pet_memories box (读写)            │              │
│  ├─ conversations box (只读)           │              │
│  └─ pet_config box (读写 persona)      │              │
│                                                        │
└────────────────────────────────────────┼───────────────┘
                                         │ 同一个 Hive
┌─ 引擎 #2 (悬浮窗) ────────────────────┼───────────────┐
│                                        │               │
│  PetWindow                             │               │
│  ├─ PetBehavior (自主行为 + 表情气泡)    │               │
│  │   └─ PetRenderer                   │               │
│  └─ MiniChat ←─────────────────────────┘               │
│      └─ PetChatService (同一 box)                      │
│                                                        │
└────────────────────────────────────────────────────────┘
```

---

## 存储结构

| Hive Box | Key | Value |
|----------|-----|-------|
| `pet_config` | `persona` | PetPersona.toJson() |
| `pet_chats` | `{id}` | {id, title, messages:[], createdAt, updatedAt} |
| `pet_chats` | `currentId` | String |
| `pet_memories` | `{id}` | PetMemory.toJson() |
| `pet_memories` | `imports` | [{importId, convId, memoryIds, title, importedAt}] |

---

## 测试策略

| 模块 | 测试类型 | 重点 |
|------|---------|------|
| PetPersona | 单元 | toJson/fromJson/template 适配 |
| PetChatService | 单元 | CRUD/buildContext/importMemories/renameChat |
| PetBehavior | Widget | 气泡显示/消失/防刷屏 |
| MiniChat | Widget | 持久化/上下文注入 |
| PetCenterScreen | Widget | 状态卡片渲染/Tab 切换 |
| PetChatScreen | Widget | 消息列表/对话切换/重命名 |
| PetMemoryScreen | Widget | 列表渲染/滑动删除 |
| PetSettingsScreen | Widget | 模板选择/试聊弹窗 |

---

## 验证方式

1. `flutter analyze` — 零新增 error
2. `flutter test` — 全部通过
3. 手动验证：
   - 抽屉 → 宠物中心 → 状态卡片实时反映宠物状态
   - 设置页 → 选模板 → 试聊 → 确认语气变化 → 保存
   - MiniChat 聊天 → 关窗 → PetCenter 打开 → 消息还在，标题已自动生成
   - 对话列表长按 → 重命名 → 确认标题更新
   - 主 App 多选对话 → 分享给糯糯 → PetMemoryScreen 看到新记忆
   - 宠物悬浮窗 → 观察到位移/翻转/饥饿气泡
   - 记忆管理 → 删除记忆和导入记录
