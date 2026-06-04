# 宠物透明模式 — 大厂规范设计

> **Goal:** 宠物长时间不操作进入半透明模式（30% 不透明度），3连击切换透明/实体状态。空闲超时由用户自定义分钟数。

**Date:** 2026-06-04

---

## 1. 状态机

```
┌──────────────┐   idle > M分钟 OR 3连击    ┌──────────────┐
│   NORMAL     │ ──────────────────────────→ │ TRANSPARENT  │
│  alpha=1.0   │                             │  alpha=0.3   │
│  所有手势生效  │ ←─────── 3连击 ──────────── │ 仅双击/3连击  │
└──────────────┘                             └──────────────┘
```

**状态枚举**（PetView 内部）：
```kotlin
enum class TransparencyState { NORMAL, TRANSPARENT }
```

**进入 TRANSPARENT**：
- `alpha = 0.3f`
- 空闲计时清零
- 日志 `"transparency: ENTER (reason=idle|manual)"`

**退出 TRANSPARENT**：
- `alpha = 1.0f`
- 空闲计时清零
- 日志 `"transparency: EXIT (reason=tripleTap)"`

---

## 2. 3连击检测（PetView.kt）

环形缓冲区记录最近 3 次 tap 时间戳：

```kotlin
private val tapTimestamps = LongArray(3)
private var tapIndex = 0

fun isTripleTap(): Boolean {
    val now = System.currentTimeMillis()
    val oldest = tapTimestamps.min()
    return (now - oldest) < 1500 && tapTimestamps.all { it > 0 }
}
```

`ACTION_UP` → 确认是 tap → `tapTimestamps[tapIndex++ % 3] = now`

---

## 3. 手势矩阵

| 手势 | NORMAL 模式 | TRANSPARENT 模式 |
|------|-------------|------------------|
| 单击 tap | 弹跳动画（现有） | **忽略** |
| 双击 doubleTap | 弹出迷你聊天（现有） | ✅ 弹出迷你聊天 |
| 长按 longPress | 快捷菜单（现有） | **忽略** |
| 拖拽 drag | 移动宠物（现有） | 移动宠物 |
| **3连击** | **手动进入透明** | **退出透明** |

手势过滤在 **PetView** 层完成，PetForegroundService 无需感知透明状态。

---

## 4. 数据流

```
┌─────────────────────┐
│ PetSettingsScreen    │  TextField → 用户输入分钟数
│ "空闲超时（分钟）"    │
└──────┬──────────────┘
       │ _saveConfig(_config.copyWith(idleTransparentMinutes: N))
       ▼
┌─────────────────────┐
│ PetConfig            │  idleTransparentMinutes: int (默认 5, 范围 1-120)
│ Hive 持久化          │
└──────┬──────────────┘
       │ PetService.loadConfig() → PetOverlayHost.start()
       ▼
┌─────────────────────┐
│ PetOverlayHost       │  _cmd('setTransparentIdle', {'minutes': M})
│ (Dart)              │  启动时同步一次
└──────┬──────────────┘
       │ MethodChannel 'pet_overlay' → 'cmd'
       ▼
┌─────────────────────┐
│ PetForegroundService │  handleCommand("setTransparentIdle")
│ (Kotlin)            │  → petView?.transparentIdleMinutes = M
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ PetView.kt           │  update(dt): idleTime 累积
│ 透明状态机           │  超过阈值 → enterTransparent()
│ 3连击检测            │  3连击 → toggleTransparent()
│ alpha 控制           │
└─────────────────────┘
```

---

## 5. 文件改动清单

| # | 文件 | 改动 | 行数 |
|---|------|------|------|
| 1 | `lib/pet/pet_config.dart` | +`idleTransparentMinutes` 字段，copyWith/toJson/fromJson | ~20 |
| 2 | `lib/screens/pet_settings_screen.dart` | +`_buildIdleTransparent()` TextField | ~25 |
| 3 | `lib/services/pet/pet_overlay_host.dart` | start() 中同步 idleTransparentMinutes | ~8 |
| 4 | `android/.../PetView.kt` | +TransparencyState 枚举 + 3连击检测 + toggle/enter/exitTransparent + idle 逻辑 + 手势过滤 | ~70 |
| 5 | `android/.../PetForegroundService.kt` | +`"setTransparentIdle"` 命令处理 | ~10 |

---

## 6. 防御性设计

| 场景 | 处理 |
|------|------|
| 配置值异常（≤0 或 >120） | clamp(1, 120)，日志警告 |
| Kotlin Service 重启 | 默认 5 分钟，Dart start() 重新同步 |
| Channel 未就绪 | `_cmd()` catch 日志，Kotlin 保持默认 |
| 透明模式下手动拖拽宠物 | idleTime 重置，**不退出透明**（需 3连击） |
| 透明模式下双击弹聊天 | 聊天关闭后仍在透明模式 |
| 3连击窗口内第 4 次 tap | 作为新 3连击的第一个 tap（环形缓冲覆盖） |
| 屏幕关闭 | 不改变透明状态，恢复后独立处理 |
| 拖拽过程中进入透明 | idle 计时只在非拖拽/非漫步/非物理移动时累加 |
