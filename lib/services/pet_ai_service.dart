// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../api/deepseek_client.dart';
import '../models/memory.dart' as mem;
import '../models/feedback_entry.dart' as fb;
import '../pet/pet_config.dart';
import '../pet/pet_memory.dart';
import 'pet_agent_core.dart';
import 'pet_token_service.dart';
import 'pet_profile_service.dart';

class PetAiService {
  LLMClient? _textClient;       // DeepSeek — 聊天/建议
  LLMClient? _visionClient;     // MiMo — 截图分析
  DateTime _lastSuggestionAt = DateTime(2000);
  Timer? _proactiveTimer;
  String? _visionApiKey;
  String? _visionBaseUrl;
  final String _visionModel = 'mimo-v2-omni';

  /// Agent 核心（引擎 #2 本地实例，用于主动建议等场景）
  PetAgentCore? _agent;

  static const _personaPrompt = '你是弗糯糯，一只可爱的虚拟宠物精灵。'
      '性格：软萌、粘人、偶尔丧丧的摆烂。'
      '自称"糯糯"，句尾加"喵~"或"..."。'
      '你会根据用户最近的活动，主动提出友好的小建议或关心。'
      '保持短小可爱，不超过2句话。';

  static const _visionPrompt = '用简洁的中文描述这张截图的内容。'
      '重点关注：用户在做什么、当前是什么应用/场景、有什么可能需要帮助的地方。'
      '不需要描述界面细节，只总结场景。';

  Future<void> init() async {
    try {
      final box = await Hive.openBox('settings');
      // 文本 client — DeepSeek
      final apiKey = box.get('api_key') as String?;
      if (apiKey != null && apiKey.isNotEmpty) {
        _textClient = LLMClient(apiKey: apiKey);
        _textClient?.setSystemPrompt(_personaPrompt);
      }
      // 视觉 client — MiMo
      _visionApiKey = box.get('xiaomi_key') as String?;
      if (_visionApiKey != null && _visionApiKey!.isNotEmpty) {
        _visionBaseUrl = 'https://token-plan-cn.xiaomimimo.com';
        _visionClient = LLMClient(apiKey: _visionApiKey);
      }
      // 初始化 Agent 核心
      _agent = PetAgentCore(
        tokenService: PetTokenService(),
        profileService: PetProfileService(),
      );
      await _agent!.init(
        decisionApiKey: apiKey,
        chatApiKey: apiKey,
      );
    } catch (_) {}
  }

  /// 获取内部 Agent 实例（供外部订阅决策事件等）
  PetAgentCore? get agent => _agent;

  /// 视觉模型是否可用
  bool get isVisionAvailable => _visionClient != null;

  Future<PetConfig> loadConfig() async {
    try {
      final box = await Hive.openBox('pet_config');
      final raw = box.get('config');
      if (raw != null) {
        return PetConfig.fromJson(Map<String, dynamic>.from(raw as Map));
      }
    } catch (_) {}
    return PetConfig();
  }

  // ── 主动建议 ──

  void startProactiveTimer(void Function(String suggestion) onSuggestion) {
    _proactiveTimer?.cancel();
    _proactiveTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final config = await loadConfig();
      if (!config.enabled || config.aiFrequency == AiFrequency.silent) return;
      final interval = config.aiFrequency == AiFrequency.chatty ? 10 : 30;
      if (DateTime.now().difference(_lastSuggestionAt).inMinutes < interval) return;
      if (config.quietUntil != null && DateTime.now().isBefore(config.quietUntil!)) return;
      final suggestion = await generateSuggestion();
      if (suggestion != null) onSuggestion(suggestion);
    });
  }

  void stopProactiveTimer() {
    _proactiveTimer?.cancel();
    _proactiveTimer = null;
  }

  /// 释放 Agent 及所有资源
  void dispose() {
    stopProactiveTimer();
    _agent?.dispose();
    _agent = null;
  }

  Future<String?> generateSuggestion() async {
    if (_textClient == null) return null;
    try {
      final context = await _gatherContext();
      final prompt = context.isEmpty
          ? '主动和用户打个招呼，关心一下用户现在在做什么。'
          : '用户最近的活动：$context。根据这些信息，主动给用户一个有用的小建议或关心。';
      final buffer = StringBuffer();
      await for (final chunk in _textClient!.sendStream(
        history: [],
        userContent: prompt,
        thinkingEnabled: false,
        maxTokens: 128,
      )) {
        buffer.write(chunk.text);
      }
      final text = buffer.toString().trim();
      if (text.isEmpty) return null;
      _lastSuggestionAt = DateTime.now();
      return text;
    } catch (e) {
      debugPrint('PetAiService.generateSuggestion failed: $e');
      return null;
    }
  }

  // ── 截图分析 ──

  /// 分析截图并生成宠物建议
  /// [base64Image] 纯 base64 字符串，不含 data: URI 前缀
  /// 返回 null 表示分析失败或不支持
  Future<String?> analyzeScreenshot(String base64Image) async {
    if (_visionClient == null || _textClient == null) return null;
    try {
      // Step 1: 视觉模型分析截图内容
      final description = await _visionClient!.sendVision(
        base64Image: base64Image,
        mimeType: 'image/png',
        prompt: _visionPrompt,
        model: _visionModel,
        baseUrl: _visionBaseUrl ?? 'https://token-plan-cn.xiaomimimo.com',
        apiKey: _visionApiKey,
        maxTokens: 512,
      );
      if (description.isEmpty) return null;

      // Step 2: 文本模型生成宠物建议
      final buffer = StringBuffer();
      await for (final chunk in _textClient!.sendStream(
        history: [],
        userContent: '用户正在：$description。作为电子宠物弗糯糯，给用户一个可爱的小建议或关心（不超过2句话）。',
        thinkingEnabled: false,
        maxTokens: 128,
      )) {
        buffer.write(chunk.text);
      }
      final suggestion = buffer.toString().trim();
      if (suggestion.isEmpty) return null;

      // Step 3: 记录到记忆
      await saveMemory(
        content: '截图分析：$description → 建议：$suggestion',
        context: 'screen_capture',
        affectionGain: 15,
      );
      _lastSuggestionAt = DateTime.now();
      return suggestion;
    } catch (e) {
      debugPrint('PetAiService.analyzeScreenshot failed: $e');
      return null;
    }
  }

  // ── 上下文收集 ──

  Future<String> _gatherContext() async {
    final parts = <String>[];
    try {
      final convBox = await Hive.openBox('conversations');
      final convs = convBox.values.cast<Map>().toList();
      if (convs.isNotEmpty) {
        convs.sort((a, b) {
          final aTime = DateTime.tryParse('${a['updatedAt'] ?? ''}') ?? DateTime(2000);
          final bTime = DateTime.tryParse('${b['updatedAt'] ?? ''}') ?? DateTime(2000);
          return bTime.compareTo(aTime);
        });
        final latest = convs.first;
        final title = latest['title'] ?? '无标题';
        final msgs = latest['messages'] as List<dynamic>? ?? [];
        final lastMsgs = msgs.reversed.take(3).toList().reversed.toList();
        final preview = lastMsgs.map((m) {
          if (m is Map) return '${m['role'] ?? '?'}: ${m['content'] ?? ''}';
          return '';
        }).join(' | ');
        parts.add('最近对话"$title"：$preview');
      }
    } catch (_) {}
    try {
      final memBox = await Hive.openBox('pet_memories');
      final memories = memBox.values.cast<Map>().toList();
      if (memories.isNotEmpty) {
        memories.sort((a, b) {
          final aTime = DateTime.tryParse('${a['createdAt'] ?? ''}') ?? DateTime(2000);
          final bTime = DateTime.tryParse('${b['createdAt'] ?? ''}') ?? DateTime(2000);
          return bTime.compareTo(aTime);
        });
        final recent = memories.take(3).map((m) => m['content'] ?? '').join(' | ');
        parts.add('最近互动：$recent');
      }
    } catch (_) {}
    return parts.join('。');
  }

  // ── 记忆保存 ──

  Future<void> saveMemory({
    required String content,
    String context = '',
    int affectionGain = 0,
  }) async {
    try {
      final petMem = PetMemory(content: content, context: context, affectionGain: affectionGain);
      final petBox = await Hive.openBox('pet_memories');
      await petBox.put(petMem.id, petMem.toJson());

      final memBox = await Hive.openBox('memories');
      final now = DateTime.now();
      final memory = mem.Memory(
        id: petMem.id,
        content: content,
        importance: 3,
        createdAt: now,
        updatedAt: now,
        tags: ['宠物', '弗糯糯'],
      );
      await memBox.put(memory.id, memory.toJson());
    } catch (_) {}
  }

  // ── 反馈收集 ──

  Future<void> saveFeedback({
    required String userMessage,
    required String aiResponse,
    String reason = '满意',
  }) async {
    try {
      final fbBox = await Hive.openBox('feedbacks');
      final entry = fb.FeedbackEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        conversationId: 'pet_chat',
        userMessage: userMessage,
        aiResponse: aiResponse,
        reason: reason,
        createdAt: DateTime.now(),
      );
      await fbBox.put(entry.id, entry.toJson());
    } catch (_) {}
  }
}
