# Changelog

## 1.1.0+2 — 2026-06-04

### Added
- Agent 集成：LLM 处理状态实时映射为宠物动画（run/talking/wave/failed）
- 状态机联动：饥饿/困倦/开心状态自动同步到原生浮窗动画和气泡
- 桌面交互：点击浮窗宠物弹出迷你聊天对话框

### Changed
- 目录重构：services 拆分为 app/ + pet/，screens/widgets 拆出 pet/ 子目录
- Lint 规则严格化：新增 60+ Dart lint 规则

### Fixed
- 宠物交互：浮窗从全屏 MATCH_PARENT 改为 WRAP_CONTENT 小窗模式
- 宠物下坠：vy 摩擦力始终生效，漫步到达清零速度
