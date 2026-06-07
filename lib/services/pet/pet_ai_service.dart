// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../api/deepseek_client.dart';
import '../../models/model_config.dart';
import '../../models/memory.dart' as mem;
import '../../models/feedback_entry.dart' as fb;
import 'knowledge/models/diary_entry.dart';
import '../../pet/pet_config.dart';
import '../../pet/pet_memory.dart';
import 'pet_logger.dart';
import '../../pet/pet_persona.dart';
import 'pet_agent_core.dart';
import 'pet_token_service.dart';
import 'pet_profile_service.dart';

class PetAiService {
  LLMClient? _textClient;       // DeepSeek — 聊天/建议
  LLMClient? _visionClient;     // MiMo — 截图分析
  DateTime _lastSuggestionAt = DateTime(2000);
  DateTime _lastDeepSuggestionAt = DateTime(2000);
  Timer? _proactiveTimer;
  bool _isGenerating = false;   // 防并发竞态
  String? _visionApiKey;
  String? _visionBaseUrl;
  final String _visionModel = 'mimo-v2-omni';
  String _chatModelId = 'deepseek-v4-pro';
  static int _idCounter = 0;
  static final String _sessionPrefix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// Agent 核心（引擎 #2 本地实例，用于主动建议等场景）
  PetAgentCore? _agent;

  // ── Hive Box 缓存（避免每次调用都 openBox）──
  Future<Box>? _settingsFuture;
  Future<Box> get _settings => _settingsFuture ??= Hive.openBox('settings');
  Future<Box>? _configFuture;
  Future<Box> get _config => _configFuture ??= Hive.openBox('pet_config');
  Future<Box>? _convFuture;
  Future<Box> get _convBox => _convFuture ??= Hive.openBox('conversations');
  Future<Box>? _memFuture;
  Future<Box> get _memBox => _memFuture ??= Hive.openBox('memories');
  Future<Box>? _petMemFuture;
  Future<Box> get _petMemBox => _petMemFuture ??= Hive.openBox('pet_memories');
  Future<Box>? _diaryV2Future;
  Future<Box> get _diaryV2 => _diaryV2Future ??= Hive.openBox('pet_diary_v2');
  Future<Box>? _petStateFuture;
  Future<Box> get _petState => _petStateFuture ??= Hive.openBox('pet_state');
  Future<Box>? _fbFuture;
  Future<Box> get _fbBox => _fbFuture ??= Hive.openBox('feedbacks');

  PetPersona get _currentPersona {
    try {
      // 优先读 PersonaStore 的 pet_persona Box
      final box = Hive.box('pet_persona');
      final raw = box.get('data');
      if (raw is String && raw.isNotEmpty) {
        return PetPersona.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      }
    } catch (_) {}
    return PetPersona(); // fallback 默认
  }

  String get _personaPrompt {
    final p = _currentPersona;
    return '你是${p.name}，一只可爱的虚拟宠物精灵。'
        '性格：软萌、粘人、偶尔丧丧的摆烂。'
        '自称"${p.style.selfReference}"，句尾加"喵~"或"..."。'
        '你会根据用户最近的活动，主动提出友好的小建议或关心。'
        '保持短小可爱，不超过2句话。';
  }

  static const _visionPrompt = '用简洁的中文描述这张截图的内容。'
      '重点关注：用户在做什么、当前是什么应用/场景、有什么可能需要帮助的地方。'
      '不需要描述界面细节，只总结场景。';

  Future<void> init() async {
    try {
      final box = await _settings;
      // 文本 client — DeepSeek
      final apiKey = box.get('api_key') as String?;
      if (apiKey != null && apiKey.isNotEmpty) {
        // 优先读取用户定制 persona，无则用默认
        String systemPrompt = _personaPrompt;
        try {
          final configBox = await _config;
          final raw = configBox.get('persona');
          if (raw != null) {
            final persona = PetPersona.fromJson(Map<String, dynamic>.from(raw as Map));
            systemPrompt = persona.systemPrompt;
          }
        } catch (_) {}
        _textClient = LLMClient(apiKey: apiKey);
        PetLogger().info('PetAiService', 'textClient created, model=$_chatModelId');
        _textClient?.setSystemPrompt(systemPrompt);
      }
      // 视觉 client — MiMo
      // 1. 优先从 pet_config 读宠物专用视觉 key
      try {
        final configBox = await _config;
        _visionApiKey = configBox.get('visionApiKey') as String?;
        _visionBaseUrl = configBox.get('visionBaseUrl') as String?;
      } catch (_) {}
      // 2. fallback：主应用 xiaomi_key
      _visionApiKey ??= box.get('xiaomi_key') as String?;
      _visionBaseUrl ??= 'https://token-plan-cn.xiaomimimo.com';

      if (_visionApiKey != null && _visionApiKey!.isNotEmpty) {
        _visionClient = LLMClient(apiKey: _visionApiKey);
        PetLogger().info('PetAiService', 'visionClient created');
      }
      // 初始化 Agent 核心（复用已有 shared 实例，避免重复创建）
      if (PetAgentCore.shared != null) {
        _agent = PetAgentCore.shared;
        PetLogger().info('PetAiService', '复用共享 PetAgentCore 实例');
      } else {
        _agent = PetAgentCore(
          tokenService: PetTokenService.instance,
          profileService: PetProfileService(),
        );
        await _agent!.init(
          decisionApiKey: apiKey,
          chatApiKey: apiKey,
        );
      }
      // 读取用户在设置中选择的聊天模型
      try {
        final configBox = await _config;
        final cm = configBox.get('chatModel');
        if (cm is String && cm.isNotEmpty) _chatModelId = cm;
      } catch (_) {}
    } catch (e) {
      PetLogger().error('PetAiService', 'init failed', e);
    }
  }

  /// 获取内部 Agent 实例（供外部订阅决策事件等）
  PetAgentCore? get agent => _agent;

  /// 视觉模型是否可用
  bool get isVisionAvailable => _visionClient != null;

  Future<PetConfig> loadConfig() async {
    try {
      final box = await _config;
      final raw = box.get('config');
      if (raw != null) {
        return PetConfig.fromJson(Map<String, dynamic>.from(raw as Map));
      }
    } catch (_) {}
    return PetConfig();
  }

  // ── 模型解析（供各方法复用）──
  Future<({String baseUrl, String chatPath, String? apiKey, String providerId})> _resolveProvider() async {
    String baseUrl = 'https://api.deepseek.com';
    String chatPath = '/v1/chat/completions';
    String? apiKey = _textClient?.apiKey;
    String providerId = 'deepseek';
    final modelInfo = ModelConfig.resolveModel(_chatModelId);
    if (modelInfo != null) {
      baseUrl = modelInfo.baseUrl;
      chatPath = modelInfo.chatPath;
      providerId = modelInfo.providerId;
      try {
        final settingsBox = await _settings;
        final key = settingsBox.get('${modelInfo.providerId}_key') as String?;
        if (key != null && key.isNotEmpty) apiKey = key;
      } catch (_) {}
    }
    return (baseUrl: baseUrl, chatPath: chatPath, apiKey: apiKey, providerId: providerId);
  }

  // ── 主动建议 ──

  void startProactiveTimer(void Function(String suggestion) onSuggestion) {
    _proactiveTimer?.cancel();
    _proactiveTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (_isGenerating) { PetLogger().trace('PetAiService', 'proactive SKIP: already generating'); return; }
      final config = await loadConfig();
      if (!config.enabled) { PetLogger().trace('PetAiService', 'proactive SKIP: pet disabled'); return; }
      if (config.aiFrequency == AiFrequency.silent) { PetLogger().trace('PetAiService', 'proactive SKIP: frequency=silent'); return; }
      final interval = config.aiFrequency == AiFrequency.chatty ? 10 : 30;
      if (DateTime.now().difference(_lastSuggestionAt).inMinutes < interval) { return; /* 太频繁，正常跳过 */ }
      if (config.quietUntil != null && DateTime.now().isBefore(config.quietUntil!)) { PetLogger().trace('PetAiService', 'proactive SKIP: quiet hours until ${config.quietUntil}'); return; }
      _isGenerating = true;
      try {
        // D8c.3: 每30分钟尝试一次深度建议（需要足够记忆）
        final minutesSinceDeep = DateTime.now().difference(_lastDeepSuggestionAt).inMinutes;
        final suggestion = minutesSinceDeep >= 30
            ? (await generateDeepSuggestion() ?? await generateSuggestion())
            : await generateSuggestion();
        if (suggestion != null) onSuggestion(suggestion);
      } finally {
        _isGenerating = false;
      }
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

  Future<void> _refreshConfig() async {
    try {
      final configBox = await _config;
      final followMain = configBox.get('followMainModel', defaultValue: true) as bool;
      if (followMain) {
        // 跟随主聊天模型
        final settingsBox = await _settings;
        _chatModelId = settingsBox.get('selectedModelId', defaultValue: 'deepseek-v4-pro') as String;
      } else {
        final cm = configBox.get('chatModel');
        if (cm is String && cm.isNotEmpty) _chatModelId = cm;
      }
    } catch (_) {}
  }

  Future<String?> generateSuggestion() async {
    if (_textClient == null) { PetLogger().warn('PetAiService', 'generateSuggestion skipped: textClient is null (no API key?)'); return null; }
    await _refreshConfig();
    try {
      final context = await _gatherContext();
      final prompt = context.isEmpty
          ? '主动和用户打个招呼，关心一下用户现在在做什么。'
          : '用户最近的活动：$context。根据这些信息，主动给用户一个有用的小建议或关心。';

      final resolved = await _resolveProvider();
      final buffer = StringBuffer();
      await for (final chunk in _textClient!.sendStream(
        history: [],
        userContent: prompt,
        model: _chatModelId,
        baseUrl: resolved.baseUrl,
        chatPath: resolved.chatPath,
        apiKey: resolved.apiKey,
        providerId: resolved.providerId,
        thinkingEnabled: false,
        maxTokens: 128,
      )) {
        buffer.write(chunk.text);
        // 追踪建议生成的 token 消耗
        if (chunk.usage != null) {
          try {
            await PetTokenService.instance.recordTokens(chat: chunk.usage!['total_tokens'] ?? 0);
          } catch (_) {}
        }
      }
      final text = buffer.toString().trim();
      if (text.isEmpty) return null;
      _lastSuggestionAt = DateTime.now();
      PetLogger().info('PetAiService', 'suggestion sent: ${text.substring(0, text.length.clamp(0, 40))}');
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
      final resolved = await _resolveProvider();
      final buffer = StringBuffer();
      await for (final chunk in _textClient!.sendStream(
        history: [],
        userContent: '用户正在：$description。作为电子宠物${_currentPersona.name}，给用户一个可爱的小建议或关心（不超过2句话）。',
        thinkingEnabled: false,
        model: _chatModelId,
        baseUrl: resolved.baseUrl,
        chatPath: resolved.chatPath,
        maxTokens: 128,
      )) {
        buffer.write(chunk.text);
        if (chunk.usage != null) {
          try {
            await PetTokenService.instance.recordTokens(chat: chunk.usage!['total_tokens'] ?? 0);
          } catch (_) {}
        }
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

  /// D8c.3: 深度建议 — 基于记忆和画像生成个性化建议
  Future<String?> generateDeepSuggestion() async {
    if (_textClient == null) return null;
    await _refreshConfig();
    try {
      final deepCtx = await _gatherDeepContext();
      if (deepCtx == null) return null; // 记忆不够，跳过
      _lastDeepSuggestionAt = DateTime.now();

      final prompt = '你是${_currentPersona.name}，用户的AI宠物伙伴。以下是你对用户的了解：\n$deepCtx\n\n'
          '请根据这些记忆和画像，给用户一个贴心的、个性化的深度建议或提醒。\n'
          '要求：\n'
          '1. 必须引用具体的记忆（比如"你上周说过..."、"我记得你喜欢..."）\n'
          '2. 语气温暖自然，像朋友聊天\n'
          '3. 不超过3句话\n'
          '4. 如果有可以帮上忙的地方，主动提出';

      final resolved3 = await _resolveProvider();
      final buffer = StringBuffer();
      await for (final chunk in _textClient!.sendStream(
        history: [],
        userContent: prompt,
        model: _chatModelId,
        baseUrl: resolved3.baseUrl,
        chatPath: resolved3.chatPath,
        maxTokens: 200,
        thinkingEnabled: false,
      )) {
        buffer.write(chunk.text);
        if (chunk.usage != null) {
          try { await PetTokenService.instance.recordTokens(chat: chunk.usage!['total_tokens'] ?? 0); } catch (_) {}
        }
      }
      final text = buffer.toString().trim();
      if (text.isEmpty) return null;
      _lastSuggestionAt = DateTime.now();
      PetLogger().info('PetAiService', 'deepSuggestion: ${text.substring(0, text.length.clamp(0, 50))}');
      return text;
    } catch (e) {
      debugPrint('PetAiService.generateDeepSuggestion failed: $e');
      return null;
    }
  }

  /// D8c.3: 收集深度上下文（记忆+画像+日记统计）
  Future<String?> _gatherDeepContext() async {
    try {
      final agent = PetAgentCore.shared;
      final kb = agent?.suggestionEngine?.knowledgeBase;
      if (kb == null) return null;

      final profile = await kb.memoryStore.buildProfileAsync();
      final all = await kb.memoryStore.loadAll();
      if (all.length < 3) return null; // 至少3条记忆才深度建议

      final parts = <String>[];

      // 兴趣
      if (profile.interests.isNotEmpty) {
        parts.add('用户的兴趣：${profile.interests.take(5).join('、')}');
      }

      // 习惯
      if (profile.habitWeights.isNotEmpty) {
        final habits = profile.habitWeights.entries
            .where((e) => e.value > 0.3)
            .map((e) => '${e.key}(${(e.value * 100).toInt()}%)')
            .join('、');
        if (habits.isNotEmpty) parts.add('用户的习惯：$habits');
      }

      // 最近记忆
      final recent = all
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final memoryLines = recent.take(5).map((m) => '- [${m.tag.name}] ${m.content}').join('\n');
      if (memoryLines.isNotEmpty) parts.add('最近记忆：\n$memoryLines');

      // 日记统计
      final todayDiary = await kb.diaryStore.loadToday();
      final todayEvents = todayDiary.where((e) => e.type != DiaryEntryType.summary).length;
      if (todayEvents > 0) parts.add('今天已和用户互动 $todayEvents 次');

      return parts.isEmpty ? null : parts.join('\n');
    } catch (_) {
      return null;
    }
  }

  // ── 上下文收集 ──

  Future<String> _gatherContext() async {
    final parts = <String>[];
    final now = DateTime.now();
    final hour = now.hour;

    // 时段描述
    final timeDesc = switch (hour) {
      >= 6 && < 9 => '现在是早上，主人刚开始新的一天',
      >= 9 && < 12 => '现在是上午工作时间',
      >= 12 && < 14 => '现在是午休时间',
      >= 14 && < 18 => '现在是下午工作时间',
      >= 18 && < 21 => '现在是傍晚放松时间',
      >= 21 || < 6 => '现在是深夜，主人可能比较疲惫',
      _ => '',
    };
    if (timeDesc.isNotEmpty) parts.add(timeDesc);

    // 最近对话
    try {
      final convBox = await _convBox;
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
        if (preview.isNotEmpty) parts.add('最近对话"$title"：$preview');
      }
    } catch (_) {}

    // 最近互动统计
    try {
      final diaryBox = await _diaryV2;
      final recentDays = <String, int>{};
      for (final v in diaryBox.values) {
        if (v is Map) {
          final ts = v['date'] as String?;
          if (ts != null) {
            final d = DateTime.tryParse(ts);
            if (d != null && now.difference(d).inHours < 24) {
              final key = '${d.hour}时';
              recentDays[key] = (recentDays[key] ?? 0) + 1;
            }
          }
        }
      }
      if (recentDays.isNotEmpty) {
        final total = recentDays.values.fold(0, (a, b) => a + b);
        parts.add('今天已和主人互动 $total 次');
      }
    } catch (_) {}

    // 用户画像
    try {
      final kb = PetAgentCore.shared?.suggestionEngine?.knowledgeBase;
      if (kb != null) {
        final profile = await kb.memoryStore.buildProfileAsync();
        if (profile.interests.isNotEmpty) {
          parts.add('主人喜欢：${profile.interests.take(5).join('、')}');
        }
        if (profile.habitWeights.isNotEmpty) {
          final habits = profile.habitWeights.entries
              .where((e) => e.value > 0.3)
              .take(3)
              .map((e) => '${e.key}(${(e.value * 100).toInt()}%)')
              .join('、');
          if (habits.isNotEmpty) parts.add('主人习惯：$habits');
        }
      }
    } catch (_) {}

    // 宠物状态
    try {
      final stateBox = await _petState;
      final raw = stateBox.get('state');
      if (raw is Map) {
        final hunger = raw['hunger'] as int? ?? 100;
        final mood = raw['mood'] as int? ?? 50;
        final energy = raw['energy'] as int? ?? 100;
        if (hunger < 50) parts.add('宠物饿了(饥饿值$hunger)');
        if (mood < 40) parts.add('宠物心情不太好(心情值$mood)');
        if (energy < 30) parts.add('宠物很累(体力值$energy)');
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
      final petBox = await _petMemBox;
      await petBox.put(petMem.id, petMem.toJson());

      final memBox = await _memBox;
      final now = DateTime.now();
      final memory = mem.Memory(
        id: petMem.id,
        content: content,
        importance: 3,
        createdAt: now,
        updatedAt: now,
        tags: ['宠物', _currentPersona.name],
      );
      await memBox.put(memory.id, memory.toJson());
      PetLogger().trace('PetAiService', 'memory saved: ${content.substring(0, content.length.clamp(0, 30))}');
    } catch (e) {
      PetLogger().error('PetAiService', 'saveMemory failed', e);
    }
  }

  // ── 反馈收集 ──

  Future<void> saveFeedback({
    required String userMessage,
    required String aiResponse,
    String reason = '满意',
  }) async {
    try {
      final fbBox = await _fbBox;
      final entry = fb.FeedbackEntry(
        id: '${_sessionPrefix}_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}',
        conversationId: 'pet_chat',
        userMessage: userMessage,
        aiResponse: aiResponse,
        reason: reason,
        createdAt: DateTime.now(),
      );
      await fbBox.put(entry.id, entry.toJson());
    } catch (e) {
      PetLogger().error('PetAiService', 'saveFeedback failed', e);
    }
  }
}
