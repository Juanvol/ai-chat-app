// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../../api/deepseek_client.dart';
import '../../models/model_config.dart';
import '../../pet/pet_persona.dart';
import '../../models/pet_state.dart';
import 'pet_logger.dart';
import 'pet_chat_service.dart';
import 'pet_token_service.dart';
import 'pet_profile_service.dart';

/// 原生浮窗动画控制通道（与 PetOverlayController 共用）
const _overlayChannel = MethodChannel('com.example.deepseek_chat/pet_overlay');
/// 宠物 Agent 桥接通道（用于获取弹窗聊天历史等）
const _agentBridge = MethodChannel('com.example.deepseek_chat/pet_agent_bridge');

enum AttentionLevel {
  l0,
  l1,
  l2,
  l3;

  Duration get interval => switch (this) {
    AttentionLevel.l0 => Duration.zero,
    AttentionLevel.l1 => const Duration(minutes: 5),
    AttentionLevel.l2 => const Duration(minutes: 2),
    AttentionLevel.l3 => const Duration(seconds: 60),
  };
}

class AgentMood {
  final double activity;
  final double sass;
  final double compliance;

  AgentMood({this.activity = 0.5, this.sass = 0.3, this.compliance = 0.8});

  AgentMood applyNoise() {
    final rng = Random();
    double noise() => (rng.nextDouble() * 0.1) - 0.05 + (rng.nextBool() ? 0.15 : -0.15);
    return AgentMood(
      activity: (activity + noise()).clamp(0.0, 1.0),
      sass: (sass + noise()).clamp(0.0, 1.0),
      compliance: (compliance + noise()).clamp(0.0, 1.0),
    );
  }
}

class AssessResult {
  final bool shouldSkipLLM;
  final String? ruleAction;
  final String? ruleContent;
  final String context;

  AssessResult({
    this.shouldSkipLLM = false,
    this.ruleAction,
    this.ruleContent,
    this.context = '',
  });
}

class ActionEntry {
  final String type;
  final String? content;
  final DateTime timestamp;

  ActionEntry({required this.type, this.content, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'type': type,
    if (content != null) 'content': content,
    'timestamp': timestamp.toIso8601String(),
  };
}

class PetAgentCore extends ChangeNotifier {
  /// 共享实例，供 main.dart 复用（避免创建第二个 PetAgentCore）
  static PetAgentCore? shared;

  /// 统一初始化入口 — 解析 API Key + 创建 + init + start
  /// 如果已有共享实例则直接返回（幂等）
  static Future<PetAgentCore?> ensureInitialized() async {
    if (shared != null) {
      PetLogger().info('Agent', 'ensureInitialized: 复用已有实例');
      return shared;
    }

    // 1. 解析 API Key：provider 专属 key → fallback 主 api_key
    String? apiKey;
    try {
      final settingsBox = await Hive.openBox('settings');
      final configBox = await Hive.openBox('pet_config');
      final chatModelId = configBox.get('chatModel') as String? ?? 'deepseek-chat';
      final modelInfo = ModelConfig.resolveModel(chatModelId);
      final providerId = modelInfo?.providerId ?? 'deepseek';
      apiKey = settingsBox.get('${providerId}_key') as String?
          ?? settingsBox.get('api_key') as String?;
      if (apiKey != null && apiKey.isNotEmpty) {
        PetLogger().info('Agent', 'ensureInitialized: provider=$providerId model=$chatModelId key=SET');
      }
    } catch (e) {
      PetLogger().error('Agent', 'ensureInitialized: API Key 解析失败', e);
    }

    if (apiKey == null || apiKey.isEmpty) {
      PetLogger().warn('Agent', 'ensureInitialized: 无可用 API Key');
      return null;
    }

    // 2. 创建 + 初始化
    final agent = PetAgentCore(
      tokenService: PetTokenService.instance,
      profileService: PetProfileService(),
    );
    await agent.init(decisionApiKey: apiKey, chatApiKey: apiKey);
    agent.start();
    PetLogger().info('Agent', 'ensureInitialized: 创建并启动完成');
    return agent;
  }

  final PetTokenService tokenService;
  final PetProfileService profileService;

  LLMClient? _decisionClient;
  LLMClient? _chatClient;
  bool _isActive = false;
  AttentionLevel _attentionLevel = AttentionLevel.l3;
  final AgentMood _mood = AgentMood();
  Timer? _perceptionTimer;
  int _consecutiveApiFailures = 0;
  bool _isPureRuleMode = false;
  CancelToken? _chatCancelToken;
  final _rng = Random();
  PetChatService? _chatSvc;
  String _decisionModelId = 'deepseek-chat';
  String _chatModelId = 'deepseek-chat';

  PetAgentCore({
    PetTokenService? tokenService,
    PetProfileService? profileService,
  })  : tokenService = tokenService ?? PetTokenService.instance,
        profileService = profileService ?? PetProfileService();

  bool get isActive => _isActive;
  AttentionLevel get attentionLevel => _attentionLevel;
  AgentMood get mood => _mood;
  bool get isPureRuleMode => _isPureRuleMode;

  Future<void> init({
    String? decisionApiKey,
    String? chatApiKey,
  }) async {
    if (decisionApiKey != null && decisionApiKey.isNotEmpty) {
      _decisionClient = LLMClient(apiKey: decisionApiKey);
    }
    if (chatApiKey != null && chatApiKey.isNotEmpty) {
      _chatClient = LLMClient(apiKey: chatApiKey);
    }
    await tokenService.loadBudget();
    PetLogger().info('Agent', 'init() budget=${tokenService.dailyBudget?.toString() ?? 'null'}');
    await _loadState();
    shared = this; // 注册共享实例，供 main.dart 复用
  }

  Future<void> _loadState() async {
    try {
      final box = await Hive.openBox('pet_config');
      final raw = box.get('agent_state');
      if (raw != null) {
        final map = Map<String, dynamic>.from(raw as Map);
        _attentionLevel = AttentionLevel.values.firstWhere(
          (e) => e.name == map['attentionLevel'],
          orElse: () => AttentionLevel.l3,
        );
      }
      // 读取用户在设置中选择的模型
      final dm = box.get('decisionModel');
      final cm = box.get('chatModel');
      if (dm is String && dm.isNotEmpty) _decisionModelId = dm;
      if (cm is String && cm.isNotEmpty) _chatModelId = cm;
      PetLogger().info('Agent', 'model loaded: decision=$_decisionModelId chat=$_chatModelId');
    } catch (e) {
      PetLogger().error('Agent', '_loadState failed', e);
    }
  }

  Future<void> _saveState() async {
    try {
      final box = await Hive.openBox('pet_config');
      await box.put('agent_state', {'attentionLevel': _attentionLevel.name});
    } catch (e) {
      PetLogger().error('Agent', '_saveState failed', e);
    }
  }

  void setAttentionLevel(AttentionLevel level) {
    _attentionLevel = level;
    _saveState();
    notifyListeners();
  }

  void start() {
    if (_isActive) return;
    PetLogger().info('Agent', 'start()');
    _isActive = true;
    _schedulePerception();
    notifyListeners();
  }

  void stop() {
    PetLogger().info('Agent', 'stop()');
    _isActive = false;
    _perceptionTimer?.cancel();
    _perceptionTimer = null;
    notifyListeners();
  }

  void _schedulePerception() {
    _perceptionTimer?.cancel();
    final interval = _attentionLevel.interval;
    if (interval == Duration.zero) return;
    _perceptionTimer = Timer(interval, () async {
      await _perceive();
      if (_isActive) _schedulePerception();
    });
  }

  Future<void> _perceive() async {
    if (!_isActive) { PetLogger().trace('Agent', 'perceive SKIP: not active'); return; }
    if (_isPureRuleMode) { PetLogger().trace('Agent', 'perceive SKIP: pure rule mode'); return; }
    if (!await tokenService.checkBudget()) { PetLogger().warn('Agent', 'perceive SKIP: budget exceeded'); return; }
    if (!_isActive) { PetLogger().trace('Agent', 'perceive SKIP: became inactive during await'); return; }

    // 从 Hive 读取真实宠物状态，替代之前的硬编码值
    int hunger = 80;
    int energy = 80;
    try {
      final stateBox = await Hive.openBox('pet_state');
      final raw = stateBox.get('state');
      if (raw != null) {
        final state = PetState.fromJson(Map<String, dynamic>.from(raw as Map));
        hunger = state.hunger;
        energy = state.energy;
      }
    } catch (_) {}

    final now = DateTime.now();
    final local = assessLocally(
      hour: now.hour,
      hunger: hunger,
      energy: energy,
      hasRecentChat: false,
    );

    if (local.shouldSkipLLM) {
      if (local.ruleAction != null) {
        await _publishAction(ActionEntry(type: local.ruleAction!, content: local.ruleContent));
      }
      return;
    }

    await _evaluate(context: local.context);
  }

  /// 三层过滤第一层：本地规则判断，不耗 token
  AssessResult assessLocally({
    required int hour,
    required int hunger,
    required int energy,
    required bool hasRecentChat,
  }) {
    if (hour >= 23 || hour < 7) {
      return AssessResult(shouldSkipLLM: true);
    }

    if (hunger < 30) {
      return AssessResult(shouldSkipLLM: false, context: '饥饿值: $hunger');
    }
    if (energy < 20) {
      return AssessResult(shouldSkipLLM: false, context: '体力值: $energy');
    }

    if (hasRecentChat) {
      return AssessResult(shouldSkipLLM: false, context: '有最近互动');
    }

    if (_rng.nextDouble() < 0.3) {
      return AssessResult(shouldSkipLLM: false);
    }

    return AssessResult(shouldSkipLLM: true);
  }

  Future<void> _refreshConfig() async {
    try {
      final box = await Hive.openBox('pet_config');
      final dm = box.get('decisionModel');
      final cm = box.get('chatModel');
      if (dm is String && dm.isNotEmpty) _decisionModelId = dm;
      if (cm is String && cm.isNotEmpty) _chatModelId = cm;
    } catch (_) {}
  }

  Future<void> _evaluate({String context = ''}) async {
    if (_decisionClient == null) return;
    await _refreshConfig();

    try {
      await _loadPersona(); // 确保 persona 已加载到上下文
      final mood = _mood.applyNoise();

      final prompt = StringBuffer();
      if (context.isNotEmpty) prompt.writeln('当前语境：$context');
      prompt.writeln('当前心情：活跃度=${mood.activity.toStringAsFixed(2)} 毒舌度=${mood.sass.toStringAsFixed(2)} 听话度=${mood.compliance.toStringAsFixed(2)}');
      prompt.writeln('决策：你现在想做什么？回复格式：{"action":"bubble/move/flip/speak/silent","content":"..."}');

      // 解析模型 → provider
      String resolvedBaseUrl = 'https://api.deepseek.com';
      String? resolvedApiKey = _decisionClient?.apiKey;
      String resolvedProviderId = 'deepseek';
      final modelInfo = ModelConfig.resolveModel(_decisionModelId);
      if (modelInfo != null) {
        resolvedBaseUrl = modelInfo.baseUrl;
        resolvedProviderId = modelInfo.providerId;
        try {
          final settingsBox = await Hive.openBox('settings');
          final key = settingsBox.get('${modelInfo.providerId}_key') as String?;
          if (key != null && key.isNotEmpty) resolvedApiKey = key;
        } catch (_) {}
      }

      final result = await _decisionClient!.send(
        history: [],
        userContent: prompt.toString(),
        model: _decisionModelId,
        baseUrl: resolvedBaseUrl,
        apiKey: resolvedApiKey,
        providerId: resolvedProviderId,
        maxTokens: 64,
        thinkingEnabled: false,
      );

      if (result.usage != null) {
        await tokenService.recordTokens(decision: result.usage!['total_tokens'] ?? 0);
      }

      _consecutiveApiFailures = 0;
      // 恢复：连续成功后退出纯规则模式
      if (_isPureRuleMode) {
        _isPureRuleMode = false;
        debugPrint('PetAgentCore: API 恢复，退出纯规则模式');
        notifyListeners();
      }

      final action = _parseAction(result.content);
      if (action != null) {
        await _publishAction(action);
      }
    } catch (e) {
      _consecutiveApiFailures++;
      if (_consecutiveApiFailures >= 3 && !_isPureRuleMode) {
        _isPureRuleMode = true;
        PetLogger().warn('Agent', 'switching to pure rule mode after $_consecutiveApiFailures failures');
        debugPrint('PetAgentCore: 连续 3 次 API 失败，切到纯规则模式');
        notifyListeners();
      }
    }
  }

  ActionEntry? _parseAction(String llmOutput) {
    try {
      final start = llmOutput.indexOf('{');
      final end = llmOutput.lastIndexOf('}');
      if (start == -1 || end == -1) return null;
      final json = llmOutput.substring(start, end + 1);
      if (json.contains('"bubble"')) {
        final content = _extractContent(json);
        return ActionEntry(type: 'bubble', content: content);
      }
      if (json.contains('"move"')) return ActionEntry(type: 'move');
      if (json.contains('"flip"')) return ActionEntry(type: 'flip');
      if (json.contains('"speak"')) {
        final content = _extractContent(json);
        return ActionEntry(type: 'speak', content: content);
      }
    } catch (_) {}
    return null;
  }

  String _extractContent(String json) {
    final match = RegExp(r'"content"\s*:\s*"([^"]*)"').firstMatch(json);
    return match?.group(1) ?? '';
  }

  Future<void> _publishAction(ActionEntry action) async {
    try {
      final box = await Hive.openBox('agent_action');
      await box.put('current', action.toJson());
      notifyListeners();
    } catch (e) {
      PetLogger().error('Agent', '_publishAction failed', e);
    }
  }

  Future<PetPersona> _loadPersona() async {
    try {
      final box = await Hive.openBox('pet_config');
      final raw = box.get('persona');
      if (raw != null) {
        return PetPersona.fromJson(Map<String, dynamic>.from(raw as Map));
      }
    } catch (_) {}
    return PetPersona();
  }

  /// 引擎 #1 是否存活（引擎 #2 调用）
  Future<bool> isEngine1Alive() async {
    try {
      final box = await Hive.openBox('agent_action');
      final raw = box.get('current');
      if (raw == null) return false;
      final map = Map<String, dynamic>.from(raw as Map);
      final timestamp = DateTime.tryParse(map['timestamp'] as String? ?? '');
      if (timestamp == null) return false;
      return DateTime.now().difference(timestamp).inSeconds < 30;
    } catch (_) {
      return false;
    }
  }

  /// 回调版聊天流 — 供应用内 UI 使用（不依赖 MethodChannel）
  Future<void> chatStream({
    required String userText,
    List<Map<String, dynamic>> history = const [],
    required void Function(String fullText) onChunk,
    required void Function() onDone,
    required void Function(String error) onError,
  }) async {
    _chatCancelToken?.cancel();
    _chatCancelToken = CancelToken();

    PetLogger().info('Agent', 'chatStream len=${userText.length}');
    if (_chatClient == null) {
      onError('糯糯还没准备好喵...稍等一下~');
      return;
    }

    await _refreshConfig();
    final persona = await _loadPersona();
    _chatClient?.setSystemPrompt(persona.systemPrompt);

    // 获取弹窗聊天历史 → 合并到上下文
    final popupHistory = await _fetchPopupHistory();

    // 解析模型 → provider
    final resolved = await _resolveChatProvider();
    final prompt = _buildChatPrompt(userText, history: history, popupHistory: popupHistory);

    try {
      final textBuffer = StringBuffer();
      DateTime lastChunkTime = DateTime.now();

      await for (final chunk in _chatClient!.sendStream(
        history: [],
        userContent: prompt,
        model: _chatModelId,
        baseUrl: resolved.baseUrl,
        apiKey: resolved.apiKey,
        providerId: resolved.providerId,
        thinkingEnabled: false,
        maxTokens: 512,
        cancelToken: _chatCancelToken,
      )) {
        textBuffer.write(chunk.text);
        if (chunk.usage != null) {
          await tokenService.recordTokens(chat: chunk.usage!['total_tokens'] ?? 0);
        }

        final now = DateTime.now();
        if (now.difference(lastChunkTime).inMilliseconds < 50) continue;
        lastChunkTime = now;

        onChunk(textBuffer.toString());
      }

      if (textBuffer.isNotEmpty) onChunk(textBuffer.toString());
      onDone();
      await _saveChatMessage(userText, textBuffer.toString());
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      onError('信号不好喵...待会再试试~');
    } catch (e) {
      debugPrint('PetAgentCore.chatStream failed: $e');
      onError('信号不好喵...待会再试试~');
    }
  }

  /// 解析聊天模型 → (baseUrl, apiKey, providerId)
  Future<({String baseUrl, String? apiKey, String providerId})> _resolveChatProvider() async {
    String baseUrl = 'https://api.deepseek.com';
    String? apiKey = _chatClient?.apiKey;
    String providerId = 'deepseek';
    final modelInfo = ModelConfig.resolveModel(_chatModelId);
    if (modelInfo != null) {
      baseUrl = modelInfo.baseUrl;
      providerId = modelInfo.providerId;
      try {
        final settingsBox = await Hive.openBox('settings');
        final key = settingsBox.get('${modelInfo.providerId}_key') as String?;
        if (key != null && key.isNotEmpty) apiKey = key;
      } catch (_) {}
    }
    return (baseUrl: baseUrl, apiKey: apiKey, providerId: providerId);
  }

  /// 获取弹窗聊天历史（来自原生 SharedPreferences）
  Future<List<Map<String, dynamic>>> _fetchPopupHistory() async {
    try {
      final raw = await _agentBridge.invokeMethod('getPopupHistory');
      if (raw is List) {
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// 构建聊天提示词（合并宠物聊天 + 弹窗聊天的历史）
  String _buildChatPrompt(String userText, {List<Map<String, dynamic>> history = const [], List<Map<String, dynamic>> popupHistory = const []}) {
    final buffer = StringBuffer();
    if (popupHistory.isNotEmpty) {
      buffer.writeln('【弹窗聊天记录】');
      for (final m in popupHistory) {
        final role = (m['isUser'] == true || m['role'] == 'user') ? '主人' : '雪乃';
        buffer.writeln('$role: ${m['text'] ?? m['content'] ?? ''}');
      }
      buffer.writeln('');
    }
    if (history.isNotEmpty) {
      buffer.writeln('【最近宠物聊天】');
      for (final m in history) {
        final role = m['role'] == 'user' ? '主人' : '雪乃';
        buffer.writeln('$role: ${m['content']}');
      }
    }
    buffer.writeln('主人说: $userText');
    buffer.writeln('请以雪乃的身份回复，保持短小可爱，不超过3句话。');
    return buffer.toString();
  }

  /// 处理引擎 #2 通过 MethodChannel 发来的聊天请求
  Future<void> handleChatRequest(
    String userText, {
    List<Map<String, dynamic>> history = const [],
    int requestId = 0,
  }) async {
    PetLogger().info('Agent', 'handleChatRequest rid=$requestId len=${userText.length}');

    // ── Wire 1: 开始处理 → run 动画 + 思考气泡 ──
    _sendOverlayCmd('playAnim', {'anim': 'run'});
    _sendOverlayCmd('showBubble', {'text': '正在思考...', 'durationMs': 5000});
    bool firstChunkSent = false;

    await chatStream(
      userText: userText,
      history: history,
      onChunk: (fullText) {
        // ── Wire 1: 首个 chunk → talking 动画 ──
        if (!firstChunkSent) {
          firstChunkSent = true;
          _sendOverlayCmd('playAnim', {'anim': 'talking'});
        }
        _sendChatChunk(fullText, requestId: requestId);
        // 同时通过 overlay 通道发给原生聊天 Dialog
        _sendOverlayCmd('chatChunk', {'text': fullText, 'isStreaming': true, 'requestId': requestId});
      },
      onDone: () {
        // ── Wire 1: 完成 → wave + 成功气泡 ──
        _sendOverlayCmd('playAnim', {'anim': 'wave'});
        _sendOverlayCmd('showBubble', {'text': '搞定啦~', 'durationMs': 3000});
        _sendChatDone(requestId: requestId);
        _sendOverlayCmd('chatDone', {'requestId': requestId});
      },
      onError: (msg) {
        // ── Wire 1: 出错 → failed + 错误气泡 ──
        _sendOverlayCmd('playAnim', {'anim': 'failed'});
        _sendOverlayCmd('showBubble', {'text': msg, 'durationMs': 4000});
        _sendChatError(msg, requestId: requestId);
        _sendOverlayCmd('chatError', {'message': msg, 'requestId': requestId});
      },
    );
  }

  void _sendChatChunk(String fullText, {required int requestId}) {
    try {
      const MethodChannel('com.example.deepseek_chat/pet_agent_bridge')
          .invokeMethod('chatChunk', {
        'fullText': fullText,
        'requestId': requestId,
      });
    } catch (e) {
      PetLogger().error('Agent', '_sendChatChunk failed', e);
    }
  }

  void _sendChatDone({required int requestId}) {
    try {
      const MethodChannel('com.example.deepseek_chat/pet_agent_bridge')
          .invokeMethod('chatDone', {'requestId': requestId});
    } catch (e) {
      PetLogger().error('Agent', '_sendChatDone failed', e);
    }
  }

  void _sendChatError(String message, {required int requestId}) {
    try {
      const MethodChannel('com.example.deepseek_chat/pet_agent_bridge')
          .invokeMethod('chatError', {
        'message': message,
        'requestId': requestId,
      });
    } catch (e) {
      PetLogger().error('Agent', '_sendChatError failed', e);
    }
  }

  /// Wire 1+2: 向原生浮窗发送动画/气泡指令
  /// 通过 pet_overlay channel → PetForegroundService.handleCommand()
  void _sendOverlayCmd(String cmd, Map<String, dynamic> args) {
    try {
      _overlayChannel.invokeMethod('cmd', {
        'cmd': cmd,
        'args': args,
      });
    } catch (e) {
      PetLogger().error('Agent', '_sendOverlayCmd($cmd) failed', e);
    }
  }

  Future<void> _saveChatMessage(String userText, String assistantText) async {
    try {
      _chatSvc ??= PetChatService();
      final chatBox = await Hive.openBox('pet_chats');
      var currentId = chatBox.get('currentId') as String?;
      if (currentId == null) {
        currentId = await _chatSvc!.createChat();
        PetLogger().info('Agent', 'chat session auto-created: $currentId');
      }
      await _chatSvc!.addMessage(currentId, 'user', userText);
      await _chatSvc!.addMessage(currentId, 'assistant', assistantText);
    } catch (e) {
      PetLogger().error('Agent', '_saveChatMessage failed', e);
    }
  }

  @override
  void dispose() {
    if (identical(shared, this)) shared = null;
    _chatCancelToken?.cancel();
    // 直接清理资源，不调 stop() — stop() 调 notifyListeners() 会在 dispose 时触发框架断言
    _perceptionTimer?.cancel();
    _perceptionTimer = null;
    _isActive = false;
    super.dispose();
  }
}
