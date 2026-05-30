import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api/deepseek_client.dart';
import 'config/theme.dart' show C;
import 'screens/home_screen.dart';
import 'services/conversation_service.dart';
import 'services/storage_service.dart';
import 'services/memory_service.dart';
import 'services/persona_service.dart';
import 'services/feedback_service.dart';
import 'services/token_stats_service.dart';
import 'services/pet_token_service.dart';
import 'services/pet_profile_service.dart';
import 'services/pet_chat_service.dart';

final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  try {
    await storage.init();
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
      ChangeNotifierProvider(create: (_) => PetTokenService()),
      ChangeNotifierProvider(create: (_) => PetProfileService()),
      ChangeNotifierProvider(create: (_) => PetChatService()),
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadThemeMode();
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
