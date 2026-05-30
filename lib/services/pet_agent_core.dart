// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../api/deepseek_client.dart';
import '../pet/pet_persona.dart';
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
  bool _isActive = false;
  AttentionLevel _attentionLevel = AttentionLevel.L3;
  AgentMood _mood = AgentMood();
  Timer? _perceptionTimer;
  int _consecutiveApiFailures = 0;
  bool _isPureRuleMode = false;
  final _rng = Random();

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
  }) async {
    if (decisionApiKey != null && decisionApiKey.isNotEmpty) {
      _decisionClient = LLMClient(apiKey: decisionApiKey);
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
      final persona = await _loadPersona();
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

      final action = _parseAction(result.content);
      if (action != null) {
        await _publishAction(action);
      }
    } catch (e) {
      _consecutiveApiFailures++;
      if (_consecutiveApiFailures >= 3) {
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

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
