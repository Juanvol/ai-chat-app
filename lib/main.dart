import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'api/deepseek_client.dart';
import 'config/theme.dart' show C;
import 'models/model_config.dart';
import 'screens/home_screen.dart';
import './services/app/conversation_service.dart';
import './services/app/storage_service.dart';
import './services/app/memory_service.dart';
import './services/app/persona_service.dart';
import './services/app/feedback_service.dart';
import './services/app/token_stats_service.dart';
import './services/pet/pet_token_service.dart';
import './services/pet/pet_profile_service.dart';
import './services/pet/pet_diary_service.dart';
import './services/pet/pet_agent_core.dart';
import './services/pet/pet_logger.dart';
import 'pet/pet_controller.dart';
import 'services/pet/pet_overlay_host.dart';

final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

/// MiniChat 注册的回调，接收来自 PetAgentCore 的流式响应（chatChunk/chatDone/chatError）
/// 单引擎架构下 MethodChannel 只能有一个 handler，main.dart 统一接收后通过此回调转发
void Function(String method, Map<String, dynamic> args)? petAgentChatSink;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PetLogger().info('App', '===== 应用启动 =====');
  final storage = StorageService();
  try {
    await storage.init();
    await PetLogger().init();  // 与引擎#2 共享日志文件，供设置页导出
  } catch (_) {
    // 初始化失败时尝试重新初始化一次
    try { await storage.reinitialize(); } catch (_) {}
  }
  final client = LLMClient(apiKey: storage.apiKey);
  try {
    final p = storage.get('system_prompt', '');
    if (p != null && p.isNotEmpty) client.setSystemPrompt(p);
  } catch (_) {}

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ConversationService(storage: storage, client: client)),
      ChangeNotifierProvider(create: (_) => MemoryService(storage: storage)),
      ChangeNotifierProvider(create: (_) => PersonaService(storage: storage)),
      ChangeNotifierProvider(create: (_) => FeedbackService(storage: storage)),
      ChangeNotifierProvider(create: (_) => TokenStatsService(storage: storage)),
      ChangeNotifierProvider(create: (_) => PetTokenService.instance),
      ChangeNotifierProvider(create: (_) { PetDiaryService.instance.init(); return PetDiaryService.instance; }),
      ChangeNotifierProvider(create: (_) { final c = PetController(); PetController.shared = c; petOverlayController.attachController(c); return c; }),
    ],
    child: DeepSeekApp(storage: storage),
  ));
}

class DeepSeekApp extends StatefulWidget {
  final StorageService storage;
  const DeepSeekApp({super.key, required this.storage});
  @override
  State<DeepSeekApp> createState() => _DeepSeekAppState();
}

class _DeepSeekAppState extends State<DeepSeekApp> with WidgetsBindingObserver {
  PetAgentCore? _petAgent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadThemeMode();
    _setupPetAgentBridge();
  }

  void _setupPetAgentBridge() {
    const MethodChannel('com.example.deepseek_chat/pet_agent_bridge')
        .setMethodCallHandler((call) async {
      switch (call.method) {
        case 'chatReq':
          final text = call.arguments['text'] as String? ?? '';
          final history = (call.arguments['history'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ?? [];
          final requestId = call.arguments['requestId'] as int? ?? 0;
          PetLogger().info('App', 'chatReq rid=$requestId len=${text.length} historyRounds=${history.length}');

          // 懒初始化 Agent（防并发竞态：_petAgentInitLock）
          try {
            await _initPetAgentOnce();
            await _petAgent!.handleChatRequest(
              text,
              history: history,
              requestId: requestId,
            );
          } catch (e) {
            PetLogger().error('App', 'chatReq handleChatRequest failed', e);
            // Agent 异常 → 通过 petAgentChatSink 回传错误
            petAgentChatSink?.call('chatError', {
              'message': '糯糯还没准备好喵...稍等一下~',
              'requestId': requestId,
            });
          }

        case 'chatChunk':
        case 'chatDone':
        case 'chatError':
          // 转发给 MiniChat 注册的回调
          petAgentChatSink?.call(
            call.method,
            Map<String, dynamic>.from(call.arguments as Map? ?? {}),
          );
      }
    });
  }

  Future<void>? _petAgentInitFuture;

  Future<void> _initPetAgentOnce() async {
    if (_petAgent != null) return;
    // 防并发竞态：多个 chatReq 同时到达时只有一个执行初始化
    if (_petAgentInitFuture != null) {
      await _petAgentInitFuture;
      return;
    }
    _petAgentInitFuture = _doInitPetAgent();
    try {
      await _petAgentInitFuture;
    } finally {
      _petAgentInitFuture = null;
    }
  }

  Future<void> _doInitPetAgent() async {
    // 优先复用 PetAiService 创建的共享实例（避免两个 Agent 同时运行）
    if (PetAgentCore.shared != null) {
      _petAgent = PetAgentCore.shared;
      PetLogger().info('Agent', '复用共享 PetAgentCore 实例');
      return;
    }
    final tokenSvc = PetTokenService.instance;
    final profileSvc = PetProfileService();
    _petAgent = PetAgentCore(
      tokenService: tokenSvc,
      profileService: profileSvc,
    );

    // 智能解析 API Key：先检查宠物选择的模型 → provider → provider专属key → fallback 主 api_key
    String? apiKey = widget.storage.apiKey;
    try {
      final configBox = await Hive.openBox('pet_config');
      final chatModelId = configBox.get('chatModel') as String? ?? 'deepseek-chat';
      final modelInfo = ModelConfig.resolveModel(chatModelId);
      if (modelInfo != null) {
        final settingsBox = await Hive.openBox('settings');
        final providerKey = settingsBox.get('${modelInfo.providerId}_key') as String?;
        if (providerKey != null && providerKey.isNotEmpty) {
          apiKey = providerKey;
          PetLogger().info('Agent', '使用 ${modelInfo.providerId} 专属 Key');
        }
      }
    } catch (e) {
      PetLogger().warn('Agent', '解析 provider key 失败，fallback 主 key: $e');
    }

    PetLogger().info('Agent', '_doInitPetAgent apiKey=${apiKey != null ? 'SET' : 'NULL'}');
    await _petAgent!.init(
      decisionApiKey: apiKey,
      chatApiKey: apiKey,
    );
    _petAgent!.start();
  }

  void _loadThemeMode() {
    final v = widget.storage.get('theme_mode', 'system') as String? ?? 'system';
    themeModeNotifier.value = switch (v) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    PetLogger().info('App', 'lifecycle: ${state.name}');
    if (!mounted) return;
    if (state != AppLifecycleState.resumed) return;
    try {
      final svc = context.read<ConversationService>();
      if (svc.isLoading) return;
      svc.refreshFromStorage();
    } catch (_) {}
  }

  @override
  void dispose() {
    // 仅当是自己创建的实例（非 PetAiService 共享实例）时才 dispose
    // 直接 dispose，不调 stop() — stop() 调 notifyListeners() 会在 dispose 时触发框架断言
    if (_petAgent != null && !identical(_petAgent, PetAgentCore.shared)) {
      _petAgent!.dispose();
    }
    _petAgent = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: themeModeNotifier,
    builder: (_, mode, __) => MaterialApp(
      title: 'AI Chat',
      debugShowCheckedModeBanner: false,
      theme: C.theme,
      darkTheme: C.darkTheme,
      themeMode: mode,
      home: const HomeScreen(),
    ),
  );
}
