# AI Chat — 项目约束

## Skill 门禁（犯错换来的）
- 功能改动/新增 → `brainstorming`（先确认方案再写代码）
- 代码修改后 → `ai-regression-testing`
- Bug/测试失败 → `systematic-debugging`（先找根因再修）
- Flutter UI → `dart-flutter-patterns` + `flutter-dart-code-review` + `material-3`
- 状态管理/导航/性能 → `flutter-expert`
- 动效/动画 → `flutter-animation`
- 构建发布 → `flutter-build-deploy`
- 测试 → `flutter-test-master` + `flutter-test-automation`
- 复杂规划 → `blueprint`

## 红线
- 只改要求的，不顺手改别的
- 删除数据前弹 AlertDialog 确认
- 改不动 ~/.claude/ 的文件（除非我说"记录"）
- UI 改动后用 `verify` 验证

## ❌✅ 代码约定
❌ StatefulWidget 里写业务逻辑 / 发网络请求
✅ 业务逻辑放 Service（ChangeNotifier），UI 通过 Consumer 读取

❌ new Dio() 随意创建 HTTP 客户端
✅ 统一通过 LLMClient.sendStream / .send

❌ import 用 package: 绝对路径
✅ 相对路径：`import '../models/message.dart'`

❌ 直接操作 Hive Box
✅ 统一通过 StorageService 读写

❌ API Key 硬编码
✅ StorageService.get('api_key') 读取

## 架构约定
- 主题通过 `C` 类访问，别硬编码颜色/字号：`C.s16`, `C.title`, `C.scheme`
- 中文 UI 字符串直接写，不做 intl
- 新模型加到 ModelConfig.builtIn，provider 加到 ModelConfig.providers
- 流式 UI 刷新节流：50ms 内最多 notifyListeners() 一次
- 新 Service extend ChangeNotifier，在 main.dart MultiProvider 注册
- 数据模型 toJson()/fromJson()，不引入额外序列化库
- ⚠️ Hive.close() 级联关闭所有 Box → 灰屏。用 deleteBoxFromDisk() 代替
