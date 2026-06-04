// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../api/deepseek_client.dart';
import '../pet/pet_persona.dart';
import 'pet_chat_service.dart';
import 'pet_token_service.dart';
import 'pet_profile_service.dart';

enum AttentionLevel {
  L0,
  L1,
  L2,
  L3;

  Duration get interval => switch (this) {
    AttentionLevel.L0 => Duration.zero,
    AttentionLevel.L1 => const Duration(minutes: 5),
    AttentionLevel.L2 => const Duration(minutes: 2),
    AttentionLevel.L3 => const Duration(seconds: 60),
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
  final PetTokenService tokenService;
  final PetProfileService profileService;

  LLMClient? _decisionClient;
  LLMClient? _chatClient;
  bool _isActive = false;
  AttentionLevel _attentionLevel = AttentionLevel.L3;
  AgentMood _mood = AgentMood();
  Timer? _perceptionTimer;
  int _consecutiveApiFailures = 0;
  bool _isPureRuleMode = false;
  CancelToken? _chatCancelToken;
  final _rng = Random();
  PetChatService? _chatSvc;

  PetAgentCore({
    PetTokenService? tokenService,
    PetProfileService? profileService,
  })  : tokenService = tokenService ?? PetTokenService(),
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
    await _loadState();
  }

  Future<void> _loadState() async {
    try {
      final box = await Hive.openBox('pet_config');
      final raw = box.get('agent_state');
      if (raw != null) {
        final map = Map<String, dynamic>.from(raw as Map);
        _attentionLevel = AttentionLevel.values.firstWhere(
          (e) => e.name == map['attentionLevel'],
          orElse: () => AttentionLevel.L3,
        );
      }
    } catch (_) {}
  }

  Future<void> _saveState() async {
    try {
      final box = await Hive.openBox('pet_config');
      await box.put('agent_state', {'attentionLevel': _attentionLevel.name});
    } catch (_) {}
  }

  void setAttentionLevel(AttentionLevel level) {
    _attentionLevel = level;
    _saveState();
    notifyListeners();
  }

  void start() {
    if (_isActive) return;
    _isActive = true;
    _schedulePerception();
    notifyListeners();
  }

  void stop() {
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
    if (!_isActive || _isPureRuleMode) return;
    if (!await tokenService.checkBudget()) return;
    if (!_isActive) return; // await 后重查，防止 dispose 后继续执行

    final now = DateTime.now();
    final local = assessLocally(
      hour: now.hour,
      hunger: 80,
      energy: 80,
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

  Future<void> _evaluate({String context = ''}) async {
    if (_decisionClient == null) return;

    try {
      await _loadPersona(); // 确保 persona 已加载到上下文
      final mood = _mood.applyNoise();

      final prompt = StringBuffer();
      if (context.isNotEmpty) prompt.writeln('当前语境：$context');
      prompt.writeln('当前心情：活跃度=${mood.activity.toStringAsFixed(2)} 毒舌度=${mood.sass.toStringAsFixed(2)} 听话度=${mood.compliance.toStringAsFixed(2)}');
      prompt.writeln('决策：你现在想做什么？回复格式：{"action":"bubble/move/flip/speak/silent","content":"..."}');

      final result = await _decisionClient!.send(
        history: [],
        userContent: prompt.toString(),
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
    } catch (_) {}
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

  /// 处理引擎 #2 通过 MethodChannel 发来的聊天请求
  Future<void> handleChatRequest(
    String userText, {
    List<Map<String, dynamic>> history = const [],
    int requestId = 0,
  }) async {
    _chatCancelToken?.cancel();
    _chatCancelToken = CancelToken();

    if (_chatClient == null) {
      _sendChatError('糯糯还没准备好喵...稍等一下~', requestId: requestId);
      return;
    }

    final persona = await _loadPersona();
    _chatClient?.setSystemPrompt(persona.systemPrompt);

    final buffer = StringBuffer();
    if (history.isNotEmpty) {
      buffer.writeln('最近对话：');
      for (final m in history) {
        final role = m['role'] == 'user' ? '主人' : '糯糯';
        buffer.writeln('$role: ${m['content']}');
      }
    }
    buffer.writeln('主人说: $userText');
    buffer.writeln('请以糯糯的身份回复，保持短小可爱，不超过3句话。');

    try {
      final textBuffer = StringBuffer();
      DateTime lastChunkTime = DateTime.now();

      await for (final chunk in _chatClient!.sendStream(
        history: [],
        userContent: buffer.toString(),
        thinkingEnabled: false,
        maxTokens: 512,
        cancelToken: _chatCancelToken,
      )) {
        textBuffer.write(chunk.text);

        final now = DateTime.now();
        if (now.difference(lastChunkTime).inMilliseconds < 50) continue;
        lastChunkTime = now;

        _sendChatChunk(textBuffer.toString(), requestId: requestId);
      }

      if (textBuffer.isNotEmpty) {
        _sendChatChunk(textBuffer.toString(), requestId: requestId);
      }
      _sendChatDone(requestId: requestId);

      await _saveChatMessage(userText, textBuffer.toString());
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) { /* 请求被取消，正常 */ }
      else { rethrow; }
    } catch (e) {
      debugPrint('PetAgentCore.handleChatRequest failed: $e');
      _sendChatError('信号不好喵...待会再试试~', requestId: requestId);
    }
  }

  void _sendChatChunk(String fullText, {required int requestId}) {
    try {
      MethodChannel('com.example.deepseek_chat/pet_agent_bridge')
          .invokeMethod('chatChunk', {
        'fullText': fullText,
        'requestId': requestId,
      });
    } catch (_) {}
  }

  void _sendChatDone({required int requestId}) {
    try {
      MethodChannel('com.example.deepseek_chat/pet_agent_bridge')
          .invokeMethod('chatDone', {'requestId': requestId});
    } catch (_) {}
  }

  void _sendChatError(String message, {required int requestId}) {
    try {
      MethodChannel('com.example.deepseek_chat/pet_agent_bridge')
          .invokeMethod('chatError', {
        'message': message,
        'requestId': requestId,
      });
    } catch (_) {}
  }

  Future<void> _saveChatMessage(String userText, String assistantText) async {
    try {
      _chatSvc ??= PetChatService();
      final chatBox = await Hive.openBox('pet_chats');
      final currentId = chatBox.get('currentId') as String?;
      if (currentId != null) {
        await _chatSvc!.addMessage(currentId, 'user', userText);
        await _chatSvc!.addMessage(currentId, 'assistant', assistantText);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _chatCancelToken?.cancel();
    stop();
    super.dispose();
  }
}
