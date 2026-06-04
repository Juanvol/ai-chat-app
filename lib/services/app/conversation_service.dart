import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../api/deepseek_client.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/model_config.dart';
import '../../models/token_usage.dart';
import '../pet/pet_logger.dart';
import 'storage_service.dart';

class ConversationService extends ChangeNotifier {
  final StorageService _storage;
  final LLMClient _client;
  List<Conversation> _conversations = [];
  Conversation? _currentConversation;
  bool _isLoading = false;
  CancelToken? _cancelToken;

  // 全局使用设置
  int globalMaxTokens = 8192;
  double globalTemperature = 0.7;
  int rateLimitPerMinute = 20;

  // 速率限制：记录最近 1 分钟内的请求时间戳
  final List<DateTime> _requestTimestamps = [];

  ConversationService({required StorageService storage, required LLMClient client})
      : _storage = storage, _client = client {
    _loadConversations();
    _loadSettings();
  }

  Conversation? get currentConversation => _currentConversation;
  bool get isLoading => _isLoading;
  StorageService get storage => _storage;
  LLMClient get client => _client;

  /// 当前是否有可用的 API Key
  bool get hasApiKey {
    final selId = _storage.selModel;
    final model = ModelConfig.builtIn.where((m) => m.id == selId).firstOrNull;
    final provider = ModelConfig.providers.where((p) => p.id == (model?.providerId ?? 'deepseek')).firstOrNull;
    final key = _storage.get('${provider?.id}_key', '') ?? '';
    if (key.isNotEmpty) return true;
    return _client.apiKey != null && _client.apiKey!.isNotEmpty;
  }

  void stopGeneration() {
    PetLogger().info('ConvSvc', 'stopGeneration');
    _cancelToken?.cancel();
  }

  void _loadSettings() {
    globalMaxTokens = _storage.get('global_max_tokens', 8192);
    globalTemperature = (_storage.get('global_temperature', 0.7) as num).toDouble();
    rateLimitPerMinute = _storage.get('rate_limit', 20);
  }

  Future<void> saveSettings({int? maxTokens, double? temperature, int? rateLimit}) async {
    if (maxTokens != null) { globalMaxTokens = maxTokens; await _storage.save('global_max_tokens', maxTokens); }
    if (temperature != null) { globalTemperature = temperature; await _storage.save('global_temperature', temperature); }
    if (rateLimit != null) { rateLimitPerMinute = rateLimit; await _storage.save('rate_limit', rateLimit); }
    notifyListeners();
  }

  void _loadConversations() {
    try {
      _conversations = _storage.getConvs();
      for (final conv in _conversations) {
        var changed = false;
        for (var i = 0; i < conv.messages.length; i++) {
          final msg = conv.messages[i];
          if (msg.isStreaming) {
            conv.messages[i] = msg.copyWith(
              isStreaming: false,
              content: msg.content.isEmpty ? '（对话中断）' : msg.content,
            );
            changed = true;
          }
        }
        if (changed) unawaited(_storage.saveConv(conv));
      }
      // 恢复上次选中的对话
      final savedId = _storage.get('current_conv_id', '') as String? ?? '';
      if (savedId.isNotEmpty && _conversations.isNotEmpty) {
        final idx = _conversations.indexWhere((c) => c.id == savedId);
        _currentConversation = idx >= 0 ? _conversations[idx] : _conversations.first;
      } else {
        _currentConversation = _conversations.isNotEmpty ? _conversations.first : null;
      }
    } catch (_) {
      // getConvs() 已对单条损坏做容错，此处仅兜底
    }
    notifyListeners();
  }

  void refreshFromStorage() {
    try {
      _conversations = _storage.getConvs();
      final currentId = _currentConversation?.id;
      if (currentId != null && _conversations.isNotEmpty) {
        final idx = _conversations.indexWhere((c) => c.id == currentId);
        _currentConversation = idx >= 0 ? _conversations[idx] : _conversations.first;
      } else {
        _currentConversation = _conversations.isNotEmpty ? _conversations.first : null;
      }
    } catch (_) {
      // 瞬态错误不覆盖已有数据
    }
    notifyListeners();
  }

  Future<void> createConversation() async {
    PetLogger().info('ConvSvc', 'createConversation');
    final now = DateTime.now();
    final conversation = Conversation(
      id: now.millisecondsSinceEpoch.toString(), title: '新对话',
      createdAt: now, updatedAt: now, messages: [],
      modelId: _storage.selModel,
    );
    _conversations.insert(0, conversation);
    _currentConversation = conversation;
    await _storage.saveConv(conversation, flush: true);
    await _storage.save('current_conv_id', conversation.id);
    notifyListeners();
  }

  void selectConversation(String id) {
    PetLogger().info('ConvSvc', 'selectConversation id=$id');
    _currentConversation = _conversations.firstWhere((c) => c.id == id);
    unawaited(_storage.save('current_conv_id', id));
    notifyListeners();
  }

  Future<void> setModel(String modelId) async {
    PetLogger().info('ConvSvc', 'setModel -> $modelId');
    await _storage.setSelModel(modelId);
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    PetLogger().info('ConvSvc', 'deleteConversation id=$id');
    await _storage.delConv(id);
    _conversations.removeWhere((c) => c.id == id);
    if (_currentConversation?.id == id) _currentConversation = _conversations.isNotEmpty ? _conversations.first : null;
    notifyListeners();
  }

  Future<void> renameConversation(String id, String newTitle) async {
    PetLogger().info('ConvSvc', 'renameConversation id=$id title=$newTitle');
    final conv = _conversations.firstWhere((c) => c.id == id);
    conv.title = newTitle;
    conv.updatedAt = DateTime.now();
    await _storage.saveConv(conv);
    notifyListeners();
  }

  Future<void> togglePin(String id) async {
    PetLogger().info('ConvSvc', 'togglePin id=$id');
    final conv = _conversations.firstWhere((c) => c.id == id);
    conv.isPinned = !conv.isPinned;
    conv.updatedAt = DateTime.now();
    await _storage.saveConv(conv);
    notifyListeners();
  }

  List<Conversation> get conversations {
    final list = List<Conversation>.from(_conversations);
    list.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  /// Full-text search across all conversations' messages
  List<({String convId, int msgIndex, String snippet})> searchAll(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final results = <({String convId, int msgIndex, String snippet})>[];
    for (final c in _conversations) {
      for (int i = 0; i < c.messages.length; i++) {
        final m = c.messages[i];
        if (m.isStreaming) continue;
        final idx = m.content.toLowerCase().indexOf(q);
        if (idx == -1) continue;
        final start = idx > 20 ? idx - 20 : 0;
        final end = (idx + q.length + 30).clamp(0, m.content.length);
        results.add((convId: c.id, msgIndex: i, snippet: '...${m.content.substring(start, end)}...'));
      }
    }
    return results;
  }

  // thinking settings
  bool get thinkingEnabled => _storage.get('thinking_enabled', true);
  String get reasoningEffort => _storage.get('reasoning_effort', 'high');

  Future<void> saveThinking({bool? enabled, String? effort}) async {
    if (enabled != null) await _storage.save('thinking_enabled', enabled);
    if (effort != null) await _storage.save('reasoning_effort', effort);
    notifyListeners();
  }

  Future<bool> sendMessage(String content,
      {String? memoryText, String? personaPrompt, String? adjustmentText,
       String? modelId, int? maxTokens}) async {
    final conversation = _currentConversation;
    if (conversation == null) { PetLogger().warn('ConvSvc', 'sendMessage: no conversation'); return false; }
    PetLogger().info('ConvSvc', 'sendMessage len=${content.length} model=${modelId ?? storage.selModel} maxTokens=${maxTokens ?? globalMaxTokens}');

    if (!hasApiKey) {
      PetLogger().warn('ConvSvc', 'sendMessage blocked: no API key');
      final userMessage = Message(
        id: '${DateTime.now().millisecondsSinceEpoch}_user',
        role: 'user', content: content, createdAt: DateTime.now(),
      );
      conversation.messages.add(userMessage);
      final errMsg = Message(
        id: '${DateTime.now().millisecondsSinceEpoch}_assistant',
        role: 'assistant', content: '请先在「设置」中配置 API Key', createdAt: DateTime.now(), isStreaming: false,
      );
      conversation.messages.add(errMsg);
      conversation.updatedAt = DateTime.now();
      await _storage.saveConv(conversation, flush: true);
      notifyListeners();
      return false;
    }

    // 速率限制检查
    if (rateLimitPerMinute > 0) {
      final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
      _requestTimestamps.removeWhere((t) => t.isBefore(cutoff));
      if (_requestTimestamps.length >= rateLimitPerMinute) {
        PetLogger().warn('ConvSvc', 'sendMessage blocked: rate limit ($rateLimitPerMinute/min)');
        final userMessage = Message(
          id: '${DateTime.now().millisecondsSinceEpoch}_user',
          role: 'user', content: content, createdAt: DateTime.now(),
        );
        conversation.messages.add(userMessage);
        final errMsg = Message(
          id: '${DateTime.now().millisecondsSinceEpoch}_assistant',
          role: 'assistant',
          content: '发送太快了喵~ 每分钟限制 $rateLimitPerMinute 条消息，请稍后再试',
          createdAt: DateTime.now(),
          isStreaming: false,
        );
        conversation.messages.add(errMsg);
        conversation.updatedAt = DateTime.now();
        await _storage.saveConv(conversation, flush: true);
        notifyListeners();
        return false;
      }
      _requestTimestamps.add(DateTime.now());
    }

    final selId = modelId ?? _storage.selModel;
    final model = ModelConfig.builtIn.where((m) => m.id == selId).firstOrNull;
    final provider = ModelConfig.providers.where((p) => p.id == (model?.providerId ?? 'deepseek')).firstOrNull;
    final providerKey = _storage.get('${provider?.id}_key', '') ?? '';

    final userMessage = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}_user',
      role: 'user', content: content, createdAt: DateTime.now(),
    );
    conversation.messages.add(userMessage);

    if (conversation.messages.length == 1) {
      conversation.title = content.length > 20 ? '${content.substring(0, 20)}...' : content;
    }

    conversation.updatedAt = DateTime.now();
    await _storage.saveConv(conversation, flush: true);

    final assistantMessage = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}_assistant',
      role: 'assistant', content: '', createdAt: DateTime.now(), isStreaming: true,
    );
    conversation.messages.add(assistantMessage);
    _isLoading = true;
    _cancelToken?.cancel();          // 取消上一个请求，防止竞态
    _cancelToken = CancelToken();
    notifyListeners();

    final savedPrompt = _storage.get('system_prompt', '') ?? '';
    final defaultPrompt = savedPrompt.isNotEmpty ? savedPrompt : '请用中文回复。对于书名、电影名、技术术语、人名等专有名词，保留原文不翻译。';
    final parts = <String>[];
    parts.add(defaultPrompt);
    if (personaPrompt != null && personaPrompt.isNotEmpty) {
      parts.add('你必须严格遵守以下角色设定来扮演人格，这是最高优先级的指令：\n$personaPrompt');
    }
    if (memoryText != null && memoryText.isNotEmpty) {
      parts.add(memoryText);
    }
    if (adjustmentText != null && adjustmentText.isNotEmpty) {
      parts.add('以下是对你回答行为的修正要求，你必须执行：\n$adjustmentText');
    }
    _client.setSystemPrompt(parts.join('\n\n'));

    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    Map<String, int>? usage;
    final svcModelId = model?.id ?? 'ds-v4-pro';
    final svcProviderId = model?.providerId ?? 'deepseek';
    try {
      final stream = _client.sendStream(
        history: conversation.messages.where((m) => !m.isStreaming).toList(),
        userContent: content,
        baseUrl: provider?.baseUrl ?? 'https://api.deepseek.com',
        apiKey: providerKey.isNotEmpty ? providerKey : _client.apiKey,
        model: model?.modelId ?? 'deepseek-v4-pro',
        maxTokens: maxTokens ?? model?.maxTokens ?? globalMaxTokens,
        thinkingEnabled: thinkingEnabled,
        reasoningEffort: reasoningEffort,
        providerId: svcProviderId,
        cancelToken: _cancelToken,
      );

      int lastNotify = 0;
      await for (final chunk in stream) {
        if (_cancelToken?.isCancelled == true) break;
        if (chunk.usage != null) {
          usage = chunk.usage;
        } else if (chunk.isThinking) {
          reasoningBuf.write(chunk.text);
        } else {
          contentBuf.write(chunk.text);
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotify > 50) {
          lastNotify = now;
          conversation.messages[conversation.messages.length - 1] =
              assistantMessage.copyWith(content: contentBuf.toString(), reasoningContent: reasoningBuf.toString());
          notifyListeners();
        }
        await Future.delayed(Duration.zero);
      }
      notifyListeners();

      if (_cancelToken?.isCancelled == true) {
        PetLogger().info('ConvSvc', 'stream cancelled, got=${contentBuf.length} chars');
        conversation.messages[conversation.messages.length - 1] =
            assistantMessage.copyWith(content: contentBuf.isEmpty ? '已停止生成' : contentBuf.toString(), reasoningContent: reasoningBuf.toString(), isStreaming: false);
      } else {
        PetLogger().info('ConvSvc', 'stream done, len=${contentBuf.length} usage=$usage');
        conversation.messages[conversation.messages.length - 1] =
            assistantMessage.copyWith(content: contentBuf.toString(), reasoningContent: reasoningBuf.toString(), isStreaming: false);
      }
    } catch (e) {
      PetLogger().error('ConvSvc', 'sendMessage failed', e);
      if (_cancelToken?.isCancelled == true) {
        conversation.messages[conversation.messages.length - 1] =
            assistantMessage.copyWith(content: '已停止生成', isStreaming: false);
      } else {
        conversation.messages[conversation.messages.length - 1] =
            assistantMessage.copyWith(content: '信号不好喵...请稍后重试~', isStreaming: false);
      }
    }

    if (usage != null) {
      try {
        await _storage.saveUsage(TokenUsage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          conversationId: conversation.id,
          modelId: svcModelId,
          providerId: svcProviderId,
          promptTokens: usage['prompt_tokens'] ?? 0,
          completionTokens: usage['completion_tokens'] ?? 0,
          createdAt: DateTime.now(),
        ));
      } catch (_) {}
    }

    conversation.updatedAt = DateTime.now();
    _isLoading = false;
    _cancelToken = null;
    await _storage.saveConv(conversation, flush: true);
    _client.setSystemPrompt(savedPrompt);
    notifyListeners();
    return true;
  }

  Future<void> regenerateMessage({
    String? memoryText, String? personaPrompt, String? adjustmentText,
    String? modelId, int? maxTokens,
  }) async {
    final cov = _currentConversation;
    if (cov == null || cov.messages.length < 2 || _isLoading) {
      PetLogger().warn('ConvSvc', 'regenerate skipped: cov=$cov msgs=${cov?.messages.length} loading=$_isLoading');
      return;
    }
    PetLogger().info('ConvSvc', 'regenerateMessage');
    final msgs = cov.messages;
    if (msgs.last.role != 'assistant' || msgs[msgs.length - 2].role != 'user') return;
    final userContent = msgs[msgs.length - 2].content;
    msgs.removeLast();
    msgs.removeLast();
    await _storage.saveConv(cov, flush: true);
    notifyListeners();
    await sendMessage(userContent,
      memoryText: memoryText,
      personaPrompt: personaPrompt,
      adjustmentText: adjustmentText,
      modelId: modelId ?? _storage.selModel,
      maxTokens: maxTokens ?? globalMaxTokens,
    );
  }
}
