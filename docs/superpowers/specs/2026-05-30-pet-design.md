# 弗糯糯虚拟电子宠物 — 设计规格说明

> 日期：2026-05-30 | 状态：待审查 | 作者：AI Chat 项目组

---

## 第 1 章：需求概述

将 AI Chat 应用从聊天工具升级为**桌面电子宠物 + AI 助手合体**——弗糯糯。

### 核心需求摘要

| # | 需求 | 用户选择 |
|---|------|---------|
| 平台 | Android 手机 | — |
| 宠物形象 | 弗糯糯（《鸣潮》弗洛洛 Q 版二创） | 用户提供序列帧 |
| 出现方式 | App 内 + App 外悬浮，尽量不遮挡 | C |
| 交互深度 | 安静陪伴 + 偶尔主动，AI 分析触发频率可调 | C + 增强 B |
| 外观 | 多图帧动画（idle/hungry/eating/happy/sleeping/talking/walking） | B |
| 养成机制 | 先轻量（喂食/玩耍/睡觉），后加社交 | C |
| AI 建议触发 | 手动 + 场景触发，频率可调 | C |
| 悬浮位置 | 自由浮动，可拖拽，缩小为头像 | B |
| 聊天方式 | 单击迷你聊天 + 双击开主 App | C |
| App 与宠物关系 | 独立前台服务，App 是配置中心 | C |
| 架构 | 双 Flutter 引擎（推荐方案 A） | A |
| 现有系统集成 | 记忆/反馈/人格/模型系统全部整合 | — |

---

## 第 2 章：系统架构总览

```
┌──────────────────────────────────────────────────┐
│                   Android OS                     │
│                                                  │
│  ┌──────────────────┐  ┌──────────────────────┐  │
│  │  Foreground      │  │  Notification        │  │
│  │  Service         │  │  "糯糯正在陪你..."    │  │
│  │  (START_STICKY)  │  │  [关闭宠物] [设置]    │  │
│  └────────┬─────────┘  └──────────────────────┘  │
│           │                                       │
│  ┌────────▼─────────────────────────────────┐    │
│  │  WindowManager (TYPE_APPLICATION_OVERLAY) │    │
│  │  FLAG_NOT_FOCUSABLE | TRANSLUCENT         │    │
│  │  ┌──────────────────────────────────┐   │    │
│  │  │  Flutter Engine #2 (宠物浮窗)     │   │    │
│  │  │  petMain()                       │   │    │
│  │  │  ├ PetRenderer (帧动画)          │   │    │
│  │  │  ├ PetInteraction (手势)         │   │    │
│  │  │  ├ PetMenu (弹出菜单)            │   │    │
│  │  │  ├ MiniChat (迷你聊天)           │   │    │
│  │  │  └ ScreenCapture (截图→AI)       │   │    │
│  │  └──────────────────────────────────┘   │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
│  ┌──────────────────────────────────────────┐    │
│  │  Flutter Engine #1 (主App)                │    │
│  │  main() → HomeScreen / PetSettings / Chat │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
│  ┌──────────────────────────────────────────┐    │
│  │  共享 Hive Boxes                          │    │
│  │  ├ pet_config (开关/频率/位置)             │    │
│  │  ├ pet_state (饥饿/心情/好感)              │    │
│  │  ├ pet_memory (AI互动记忆)                │    │
│  │  ├ personas → "弗糯糯"人格                │    │
│  │  └ feedbacks → 宠物互动反馈               │    │
│  └──────────────────────────────────────────┘    │
└──────────────────────────────────────────────────┘
```

### 关键架构决策

| 决策 | 方案 | 原因 |
|------|------|------|
| 双引擎 | 2 个 FlutterEngine | 宠物独立渲染、独立生命周期 |
| 通信 | Hive Box watch() | 零延迟共享、无需 MethodChannel，改即生效 |
| 保活 | START_STICKY | Service 被杀后系统自动重启 |
| 懒加载 | 引擎 #2 按需创建/销毁 | 宠物关闭时零内存占用 |
| 内存保护 | 系统内存压力 → 释放引擎 #2 | Service 保留，内存回稳后重建 |

---

## 第 3 章：组件拆解

### 新增文件清单

```
lib/
├── pet/                          ← 新增 pet 模块
│   ├── pet_main.dart             ← 引擎 #2 入口 (@pragma('vm:entry-point'))
│   ├── pet_window.dart           ← 悬浮窗主体（透明底、置顶、可缩）
│   ├── pet_renderer.dart         ← 帧动画播放器
│   ├── pet_interaction.dart      ← 拖拽/点击/双击手势
│   ├── pet_menu.dart             ← 弹出菜单（喂食/玩耍/聊天/截图）
│   ├── mini_chat.dart            ← 迷你聊天泡泡
│   ├── pet_state.dart            ← 养成数据模型
│   ├── pet_config.dart           ← 配置模型
│   ├── pet_memory.dart           ← 宠物互动记忆模型
│   └── pet_controller.dart       ← 宠物逻辑中枢（状态机）
├── services/
│   └── pet_service.dart          ← 前台服务管理 + 双引擎通信
├── api/
│   └── screen_capture.dart       ← 截图工具（MediaProjection → AI）
└── screens/
    └── pet_settings_screen.dart  ← 主 App 里的宠物设置页
```

### 各组件职责

| 组件 | 引擎 | 职责 |
|------|------|------|
| `pet_main.dart` | #2 | Flutter 引擎入口，只初始化 Hive → runApp(透明窗口) |
| `pet_window.dart` | #2 | WindowManager 配置（位置/大小/透明度），包裹 PetRenderer |
| `pet_renderer.dart` | #2 | 根据 pet_state.status 切换帧动画，AnimationController 12.5fps |
| `pet_interaction.dart` | #2 | 拖拽移动、单击呼叫菜单、双击打开主 App |
| `pet_menu.dart` | #2 | 弧形弹出 4 菜单项（喂食/玩耍/聊天/截图帮看） |
| `mini_chat.dart` | #2 | 迷你输入框 + 气泡回复，复用 LLMClient，3 秒无交互收起 |
| `pet_controller.dart` | #2 | 状态机驱动：idle→hungry→eating→happy→sleepy→sleeping→talking |
| `pet_state.dart` | 共享 | hunger(0-100), mood(0-100), energy(0-100), affection_level |
| `pet_config.dart` | 共享 | enabled, ai_frequency, trigger_scenes, pet_x, pet_y, skin_name |
| `pet_memory.dart` | 共享 | AI 互动记忆（触发场景、建议内容、好感增益） |
| `pet_service.dart` | 共享 | 管理前台 Service 启停、状态同步（Hive.watch） |
| `screen_capture.dart` | #2 | MediaProjection 截图 → Base64 → MiMo vision 分析 |
| `pet_settings_screen.dart` | #1 | 主 App 设置：开关/频率/皮肤/场景/自启 |

---

## 第 4 章：核心组件详细设计

### 4.1 宠物状态机

```
                    ┌──────────┐
           ┌──────►│  IDLE    │◄─────────┐
           │       │ (默认待机) │          │
           │       └────┬─────┘          │
           │            │                │
      hunger<30    click/hunger>30  ai_trigger
           │            │                │
           ▼            ▼                │
     ┌──────────┐ ┌──────────┐    ┌─────┴─────┐
     │  HUNGRY  │ │  SLEEP   │    │  TALKING  │
     │ (饥饿动画) │ │ (犯困动画) │    │ (提出建议) │
     └────┬─────┘ └────┬─────┘    └─────┬─────┘
          │            │                │
     用户喂食      醒来/互动          用户关闭/超时
          │            │                │
          ▼            ▼                │
     ┌──────────┐       ┌───────┐      │
     │  EATING  │       │ HAPPY │      │
     │ (吃饭动画) │──→──│ (开心) │      │
     └──────────┘       └───────┘      │
          │                            │
          └──────────◄─────────────────┘
```

```dart
// Flutter 3.24 / Dart 3.5
enum PetStatus { idle, hungry, eating, happy, sleepy, sleeping, talking }

class PetController extends ChangeNotifier {
  PetState _state = PetState();
  Timer? _decayTimer;

  void start() {
    _decayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _state = _state.copyWith(
        hunger: (_state.hunger - 1).clamp(0, 100),
        mood: (_state.mood - 0.5).clamp(0, 100),
        energy: (_state.energy - 1).clamp(0, 100),
      );
      _checkAutoTransition();
      notifyListeners();
      PetService.updatePetState(_state); // 持久化
    });
  }

  void _checkAutoTransition() {
    if (_state.hunger < 30 && _state.status == PetStatus.idle)
      _state = _state.copyWith(status: PetStatus.hungry);
    if (_state.energy < 20 && _state.status == PetStatus.idle)
      _state = _state.copyWith(status: PetStatus.sleepy);
  }

  void feed() => _state = _state.copyWith(hunger: 100, status: PetStatus.eating);
  void play() => _state = _state.copyWith(mood: 100, status: PetStatus.happy);
}
```

### 4.2 帧动画播放器

```dart
class PetRenderer extends StatefulWidget {
  final PetStatus status;
  final String skinPath;
  // ...
}

class _PetRendererState extends State<PetRenderer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late List<ImageProvider> _frames;

  static const _frameCounts = {
    PetStatus.idle: 54,    PetStatus.hungry: 63,
    PetStatus.talking: 63, PetStatus.sleeping: 17,
    // eating/happy/walking 待用户提供素材，缺失时回退到 idle 动画
  };

  @override
  void initState() {
    super.initState();
    _loadFrames();
    _ac = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _frames.length * 80),
    )..repeat();
  }

  void _loadFrames() {
    final count = _frameCounts[widget.status] ?? 54;
    final dir = '${widget.skinPath}/${widget.status.name}';
    _frames = List.generate(count,
      (i) => FileImage(File('$dir/frame_${i.toString().padLeft(2, '0')}.png')));
  }

  @override
  Widget build(BuildContext context) {
    final idx = (_ac.value * _frames.length).floor().clamp(0, _frames.length - 1);
    return Image(image: _frames[idx], width: 120, height: 120);
  }
}
```

### 4.3 右键菜单 → 弧形弹出

```
        [聊天]   [截图]
      ──              ──
    /                    \
   [                       ]
   │      弗糯糯 🐾        │
   [                       ]
    \                    /
      ──              ──
        [喂食]   [玩耍]
```

### 4.4 迷你聊天泡泡

```
┌─────────────────────┐
│ 糯糯："需要我帮你     │
│  看看这段教案吗？"    │
│ [输入框]      [发送]  │
│ [截图] [语音] [关闭]  │
└─────────────────────┘
```

- 复用现有 `LLMClient.sendStream`
- 最大高度 200px
- 3 秒无交互自动收起
- 使用弗糯糯人格 systemPrompt

### 4.5 屏幕截图 + AI 建议

```
1. 用户触发/场景触发
2. MediaProjection API 截图 → Bitmap
3. Base64 编码
4. 发给 MiMo vision 分析屏幕内容
5. 提取上下文 → 生成建议 prompt → DeepSeek 生成建议
6. 弗糯糯气泡："你在备课吗？需要我帮忙设计课堂活动吗？"
```

### 4.6 设置页面

| 设置项 | 类型 | 默认值 |
|--------|------|--------|
| 开启弗糯糯 | Switch | false |
| AI 主动建议频率 | Slider (安静/偶尔/话多) | 偶尔 |
| 触发场景 | MultiSelect | 全部 |
| 宠物皮肤 | Dropdown | 弗糯糯（默认） |
| 浮动位置 | 坐标 | 靠右边缘 |
| 开机自启 | Switch | false |
| 免打扰时段 | TimePicker | 无 |

---

## 第 5 章：Android 原生集成

### 5.1 权限声明

```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<service
    android:name=".PetForegroundService"
    android:exported="false"
    android:foregroundServiceType="specialUse" />
```

### 5.2 前台服务关键代码

```kotlin
class PetForegroundService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "START_PET" -> showPetWindow()
            "STOP_PET" -> hidePetWindow()
        }
        return START_STICKY
    }

    private fun showPetWindow() {
        val params = WindowManager.LayoutParams(
            WRAP_CONTENT, WRAP_CONTENT,
            TYPE_APPLICATION_OVERLAY,
            FLAG_NOT_FOCUSABLE or FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        petView = flutterEngine?.renderSurfaceView
        windowManager?.addView(petView, params)
    }
}
```

### 5.3 Flutter 引擎 #2 入口

```dart
@pragma('vm:entry-point')
void petMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PetWindow());
}
```

### 5.4 双引擎通信

不搞 MethodChannel，直接用 Hive 共享：

```dart
class PetService {
  // 引擎 #1 写
  Future<void> togglePet(bool enabled) async {
    await Hive.box('pet_config').put('enabled', enabled);
    if (enabled) _startForegroundService();
    else _stopForegroundService();
  }

  // 引擎 #2 监听
  Stream<void> watchConfig() => Hive.box('pet_config').watch();
}
```

### 5.5 启动流程

```
用户点"开启弗糯糯"
  → checkPermission(SYSTEM_ALERT_WINDOW)
    → 无权限 → 引导去系统设置
    → 有权限
  → startForegroundService(action: "START_PET")
  → 创建 FlutterEngine #2 → run petMain()
  → WindowManager.addView(petView)
  → 通知栏："弗糯糯正在陪你 🐾" [关闭] [设置]
```

### 5.6 新增依赖

```yaml
dependencies:
  flutter_background_service: ^5.0.0
  window_manager: ^0.4.0
  flutter_local_notifications: ^18.0.0
  shared_preferences: ^2.3.0
```

---

## 第 6 章：数据模型与持久化

### 6.1 PetState（养成数据）— Box `pet_state`

```dart
class PetState {
  final int hunger;           // 0-100，每分钟-1
  final int mood;             // 0-100，玩耍+30
  final int energy;           // 0-100，睡觉恢复
  final int affection;        // 0-999，只增不减
  final PetStatus status;
  final DateTime lastFed;
  final int totalInteractions;
}
```

| 属性 | 变化速率 | <30 行为 |
|------|---------|---------|
| hunger | -1/min | hungry 动画 |
| mood | -0.5/min | 丧表情 |
| energy | -1/min | sleepy → sleeping |
| affection | 只增 | 喂食+10, 玩耍+20, 聊天+5, 截图帮+15 |

### 6.2 PetConfig（配置）— Box `pet_config`

```dart
class PetConfig {
  final bool enabled;
  final AiFrequency aiFrequency;      // silent/occasional/chatty
  final Set<TriggerScene> triggerScenes;
  final int petX, petY;
  final double petScale;             // 0.5-1.5
  final String skinName;
  final bool autoStart;
  final DateTime? quietUntil;
}
```

### 6.3 皮肤文件系统

```
用户存储/
└── pet_skins/
    └── funuonuo/
        ├── idle/      54帧
        ├── hungry/    63帧
        ├── talking/   63帧
        ├── sleeping/  17帧
        ├── eating/    待提供
        ├── happy/     待提供
        └── walking/   待提供
```

### 6.4 帧命名规范

每帧文件按 `frame_00.png`、`frame_01.png`... 递增编号，从 00 开始，用两位数补零。
状态目录名与 `PetStatus` 枚举值完全一致（小写），例如：
```
funuonuo/idle/frame_00.png ~ frame_53.png  (54帧)
funuonuo/hungry/frame_00.png ~ frame_62.png (63帧)
```

缺失的状态目录 → `PetRenderer` 自动回退到 `idle` 目录。

### 6.5 皮肤导入流程

用户在主 App 设置中 → "添加新皮肤" → 选择包含各状态子文件夹的父目录 → 验证目录结构完整性（至少含 `idle/`） → 复制到 `pet_skins/custom_xx/` → 更新 `PetConfig.skinName`。

### 6.6 自动存档策略

| 事件 | 时机 |
|------|------|
| 状态变化 | 每次 notifyListeners() 后写 Hive |
| 配置修改 | 用户点保存时写入 |
| 引擎销毁 | dispose() 中写完整快照 |
| 崩溃恢复 | START_STICKY → 从 Hive 读最后一次存档 |

---

## 第 7 章：与现有系统集成

### 7.1 记忆系统 (MemoryService)

```
PetController 收集上下文
  → MemoryService.addMemory(
       title: "帮用户看教案",
       content: "...",
       tags: ["宠物","教案"],
       importance: 3)
  → 主App 记忆页：弗糯糯互动时间线
```

记忆提取增强：`memory_extractor.dart` 新增宠物模式，提取用户行为模式。

### 7.2 人格系统 (PersonaService)

```dart
final funuonuoPersona = Persona(
  name: '弗糯糯',
  systemPrompt: '''
你是弗糯糯，一只可爱的虚拟宠物精灵。
性格：软萌、粘人、偶尔丧丧的摆烂
自称"糯糯"，句尾加"喵~"或"..."
保持短回复，像宠物一样简洁可爱，不超过3句话
''',
  temperature: 0.8,
  maxTokens: 512,
);
```

用户可切换人格：弗糯糯（默认）/ 智乃 / 自定义。

### 7.3 反馈系统 (FeedbackService)

```
迷你聊天结束 3 秒后 → [👍 有用] [👎 废话]
  → FeedbackEntry(type: "pet_interaction", rating, context)
  → 👍多的场景自动提高触发频率
  → 👎多的场景降低频率或暂停
```

### 7.4 模型系统 (ModelConfig)

| 交互类型 | 模型 | 原因 |
|---------|------|------|
| 迷你聊天 | deepseek-v4-pro | 快、便宜 |
| 屏幕截图 | mimo-v2-omni | 视觉强、免费 |
| 主动建议 | deepseek-v4-pro | 轻量文本 |
| 记忆提取 | deepseek-v4-pro | 复用现有 |

---

## 第 8 章：错误处理与边界情况

### 8.1 权限被拒
- 弹 Dialog 引导用户去系统设置
- resume 时自动检测权限 → 启动宠物

### 8.2 电量与性能
- 电量<15% → 停动画、切静态图
- 屏幕关闭 → 0fps
- 帧丢 >16ms → 降分辨率

### 8.3 崩溃恢复
- `STICKY` → Service 自动重启
- 引擎 #2 崩 → Service.onCreate 重建
- 主 App 开着 → SnackBar "糯糯打了个盹，已恢复"
- 主App 关着 → 静默恢复

### 8.4 边界清单

| 边界 | 处理 |
|------|------|
| 电话/短信 | 缩放 0.3x，挂断 5s 恢复 |
| 横竖屏 | 重 clamp 坐标 |
| 折叠屏 | 限制当前 Display |
| 分屏 | 限制上半区，0.6x |
| IME 弹起 | 移上半屏 |
| 长期不互动 (>6h) | 深度休眠：停动画 + 0.3x + 呼吸浮动 |
| MiMo API 挂了 | "信号不好，待会再帮你~" 降级手动 |
| 存储<100MB | 裁剪记忆，只保留 50 条 |

### 8.5 Android 版本兼容

| 版本 | 实现 | 注意 |
|------|------|------|
| 8-9 | TYPE_APPLICATION_OVERLAY | 手动授权 |
| 10-11 | + FOREGROUND_SERVICE_TYPE_SPECIAL_USE | Play Store 审核 |
| 12+ | 同上 | MIUI/ColorOS 兼容处理 |
| 14+ | foregroundServiceType manifest 声明 | 通知不可隐藏 |

---

## 第 9 章：测试策略

### 分层覆盖

| 层级 | 工具 | 目标 |
|------|------|------|
| 单元测试 | flutter test | ≥90% (模型/状态机/序列化) |
| Widget 测试 | flutter test | ≥70% (渲染/菜单/聊天) |
| 集成测试 | integration_test | 核心路径 (双引擎/Hive同步) |
| 原生测试 | JUnit | 关键路径 (Service/权限/截图) |

### 建议测试文件结构

```
test/
└── pet/
    ├── pet_state_test.dart
    ├── pet_config_test.dart
    ├── pet_controller_test.dart
    ├── pet_service_test.dart
    ├── pet_renderer_test.dart
    ├── pet_menu_test.dart
    ├── mini_chat_test.dart
    └── pet_interaction_test.dart
integration_test/
└── pet/
    ├── pet_engine_test.dart
    └── pet_persona_test.dart
```

### 运行命令

```bash
flutter test test/pet/
flutter test integration_test/pet/
./gradlew :app:testDebugUnitTest
```

---

## 第 10 章：实施顺序

| 阶段 | 内容 | 预估工作量 |
|------|------|-----------|
| **1. 地基** | PetState/PetConfig 模型 + PetController 状态机 + 单元测试 | 第一步 |
| **2. 渲染** | PetRenderer 帧动画 + PetWindow 透明悬浮窗 + Widget 测试 | 第二步 |
| **3. 原生** | PetForegroundService + WindowManager + 权限 + 原生测试 | 第三步 |
| **4. 交互** | PetInteraction 手势 + PetMenu 菜单 + MiniChat | 第四步 |
| **5. AI 集成** | ScreenCapture + MiMo Vision + DeepSeek 建议 + 人格/记忆/反馈 | 第五步 |
| **6. 养成** | 衰减 Timer + 喂食/玩耍 + 好感度 + 存档 | 第六步 |
| **7. 设置** | PetSettingsScreen + 皮肤导入 + 场景配置 | 第七步 |
| **8. 打磨** | 边界情况 + 性能优化 + 兼容性适配 | 第八步 |

---

---

## 附录：范围分解说明

本规格涉及 5 个独立子系统，建议分开实施：

1. **桌面悬浮窗引擎**（阶段 1-3）— 可独立交付，"弗糯糯能出现在桌面上"
2. **宠物渲染系统**（阶段 2）— 帧动画播放，与引擎耦合但可独立测试
3. **宠物养成机制**（阶段 6）— 衰减/喂食/存档，依赖引擎和渲染
4. **AI 助手能力**（阶段 5）— 截图/建议/人格/记忆，依赖引擎和 LLM
5. **设置与打磨**（阶段 7-8）— 依赖以上全部

每个子系统完成后应能独立验证，不阻塞其他子系统。

---

*文档结束 — 待用户审查通过后进入 writing-plans 阶段*
