// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/pet_ai_service.dart';
import '../services/pet_service.dart';
import 'pet_controller.dart';
import 'pet_state.dart';
import 'pet_renderer.dart';
import 'pet_interaction.dart';
import 'pet_menu.dart';
import 'mini_chat.dart';
import 'pet_suggestion.dart';
import 'pet_behavior.dart';

class PetWindow extends StatefulWidget {
  const PetWindow({super.key});

  @override
  State<PetWindow> createState() => _PetWindowState();
}

class _PetWindowState extends State<PetWindow> {
  static const _channel = MethodChannel('com.example.deepseek_chat/pet_window');

  PetController? _controller;
  PetAiService? _aiService;
  bool _showMenu = false;
  bool _showChat = false;
  String? _suggestion;
  bool _initialized = false;
  bool _screenOn = true;
  int _batteryLevel = 100;
  bool _charging = false;
  double _petScale = 1.0;

  @override
  void initState() {
    super.initState();
    _setupMethodHandler();
    _initPet();
  }

  void _setupMethodHandler() {
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'onBatteryChanged':
          final level = args?['level'] as int? ?? 100;
          final charging = args?['charging'] as bool? ?? false;
          if (mounted) setState(() { _batteryLevel = level; _charging = charging; });
        case 'onScreenOff':
          if (mounted) setState(() => _screenOn = false);
        case 'onScreenOn':
          if (mounted) setState(() => _screenOn = true);
      }
    });
  }

  Future<void> _initPet() async {
    PetState saved = PetState();
    try {
      saved = await PetService.loadState();
    } catch (_) {}
    if (!mounted) return;
    _controller = PetController(
      initialState: saved,
      onStateChanged: (s) {
        try { PetService.saveState(s); } catch (_) {}
      },
    );
    _controller!.start();
    _aiService = PetAiService();
    await _aiService!.init();
    _aiService!.startProactiveTimer((s) {
      if (mounted) setState(() => _suggestion = s);
    });
    try {
      final config = await PetService.loadConfig();
      if (mounted) setState(() => _petScale = config.petScale);
      // 恢复上次保存的窗口位置
      if (config.petX != 0 || config.petY != 200) {
        try {
          await _channel.invokeMethod('setWindowPos', {'x': config.petX, 'y': config.petY});
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) setState(() => _initialized = true);
  }

  String? _moodEmoji() {
    final s = _controller?.state;
    if (s == null) return null;
    return switch (s.status) {
      PetStatus.hungry => '🍖',
      PetStatus.eating => '😋',
      PetStatus.happy => '😸',
      PetStatus.sleepy => '💤',
      PetStatus.sleeping => '💤',
      PetStatus.talking => '💬',
      PetStatus.idle => s.mood > 60 ? '😊' : s.mood > 30 ? '😐' : '😞',
    };
  }

  bool get _ecoMode =>
      !_screenOn || _batteryLevel < 15 && !_charging || (_controller?.isDeepSleeping ?? false);

  @override
  void dispose() {
    _aiService?.dispose();
    if (_controller != null) {
      try { PetService.saveState(_controller!.state); } catch (_) {}
      _controller!.dispose();
    }
    super.dispose();
  }

  void _wakeUp() {
    if (_controller?.isDeepSleeping ?? false) _controller?.wakeUp();
  }

  void _onTap() {
    if (_showChat) return;
    _wakeUp();
    setState(() { _showMenu = false; _showChat = true; });
  }

  void _onDoubleTap() {
    _wakeUp();
    try { _channel.invokeMethod('openMainApp'); } catch (_) {}
  }

  void _onLongPress() {
    if (_showChat) return;
    _wakeUp();
    setState(() => _showMenu = !_showMenu);
  }

  void _dismissMenu() => setState(() => _showMenu = false);
  void _dismissChat() {
    _controller?.stopChatting();
    setState(() => _showChat = false);
  }

  void _onFeed() { _wakeUp(); _controller?.feed(); _dismissMenu(); }
  void _onPlay() { _wakeUp(); _controller?.play(); _dismissMenu(); }
  void _onChatAction() { _wakeUp(); _controller?.chat(); _dismissMenu(); setState(() => _showChat = true); }
  void _onSleep() { _wakeUp(); _controller?.sleep(); _dismissMenu(); }

  void _onSuggestionChat() {
    _wakeUp();
    _controller?.chat(); // 设置 talking 状态
    setState(() { _suggestion = null; _showChat = true; });
  }

  void _dismissSuggestion() => setState(() => _suggestion = null);

  Future<void> _savePosition() async {
    try {
      final result = await _channel.invokeMethod('getWindowPos');
      final map = Map<String, dynamic>.from(result as Map);
      final x = (map['x'] as num?)?.toInt() ?? 0;
      final y = (map['y'] as num?)?.toInt() ?? 0;
      final config = await PetService.loadConfig();
      await PetService.saveConfig(config.copyWith(petX: x, petY: y));
    } catch (_) {}
  }

  void _onChatFeedback(String userMsg, String aiMsg, bool liked) {
    _aiService?.saveFeedback(
      userMessage: userMsg,
      aiResponse: aiMsg,
      reason: liked ? '满意' : '不满意',
    );
  }

  void _onChatMemory() {
    _aiService?.saveMemory(content: '和弗糯糯聊天互动', context: 'pet_chat', affectionGain: 5);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: _initialized && _controller != null
            ? ListenableBuilder(
                listenable: _controller!,
                builder: (_, __) => _buildContent(),
              )
            : const SizedBox(width: 120, height: 120),
      ),
    );
  }

  Widget _buildContent() {
    if (_showChat) {
      return MiniChat(
        onClose: _dismissChat,
        onFeedback: _onChatFeedback,
        onMemorySave: _onChatMemory,
        aiService: _aiService,
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_suggestion != null)
              PetSuggestion(
                text: _suggestion!,
                onChat: _onSuggestionChat,
                onDismiss: _dismissSuggestion,
              ),
            PetInteraction(
              onTap: _onTap,
              onDoubleTap: _onDoubleTap,
              onLongPress: _onLongPress,
              onDragEnd: _savePosition,
              child: PetBehavior(
                ecoMode: _ecoMode,
                child: PetRenderer(
                  status: _controller?.state.status ?? PetStatus.idle,
                  size: 120 * _petScale,
                  ecoMode: _ecoMode,
                  moodEmoji: _moodEmoji(),
                ),
              ),
            ),
          ],
        ),
        if (_showMenu)
          Positioned.fill(
            child: PetMenu(
              onFeed: _onFeed,
              onPlay: _onPlay,
              onChat: _onChatAction,
              onSleep: _onSleep,
              onDismiss: _dismissMenu,
            ),
          ),
      ],
    );
  }
}
