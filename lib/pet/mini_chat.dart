// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../api/deepseek_client.dart';
import '../models/message.dart';
import '../services/pet_feature_flags.dart';
import '../services/pet_ai_service.dart';
import '../services/pet_token_service.dart';
import '../pet/pet_persona.dart';

class MiniChat extends StatefulWidget {
  final VoidCallback onClose;
  final void Function(String userMsg, String aiMsg, bool liked)? onFeedback;
  final VoidCallback? onMemorySave;
  final PetAiService? aiService;

  const MiniChat({
    super.key,
    required this.onClose,
    this.onFeedback,
    this.onMemorySave,
    this.aiService,
  });

  @override
  State<MiniChat> createState() => _MiniChatState();
}

class _MiniChatState extends State<MiniChat> {
  static const _channel = MethodChannel('com.example.deepseek_chat/pet_window');
  static const _agentChannel = MethodChannel('com.example.deepseek_chat/pet_agent_bridge');
  static const _personaPrompt = '你是弗糯糯，一只可爱的虚拟宠物精灵。'
      '性格：软萌、粘人、偶尔丧丧的摆烂。'
      '自称"糯糯"，句尾加"喵~"或"..."。'
      '保持短回复，像宠物一样简洁可爱，不超过3句话。';

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatLine>[];
  LLMClient? _client;
  Timer? _idleTimer;
  CancelToken? _cancelToken;
  bool _isLoading = false;
  int _lastFeedbackIndex = -1;
  int _agentRequestId = 0;
  Timer? _responseTimeout;
  int _agentAssistantIndex = -1;
  PetAiService? _aiService;
  int _lastSummarizedIndex = 0;

  @override
  void initState() {
    super.initState();
    _aiService = widget.aiService;
    _initClient();
    _expandWindow();
    _resetIdleTimer();
    _setupAgentHandler();
  }

  @override
  void dispose() {
    _agentChannel.setMethodCallHandler(null);
    _cancelToken?.cancel();
    _responseTimeout?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _idleTimer?.cancel();
    _shrinkWindow();
    super.dispose();
  }

  Future<void> _initClient() async {
    try {
      final box = await Hive.openBox('settings');
      final apiKey = box.get('api_key') as String?;
      if (apiKey != null && apiKey.isNotEmpty) {
        _client = LLMClient(apiKey: apiKey);
        // 读自定义 persona，无则 fallback 默认
        String prompt = _personaPrompt;
        try {
          final configBox = await Hive.openBox('pet_config');
          final raw = configBox.get('persona');
          if (raw != null) {
            final p = PetPersona.fromJson(Map<String, dynamic>.from(raw as Map));
            if (p.systemPrompt.isNotEmpty) prompt = p.systemPrompt;
          }
        } catch (_) {}
        _client!.setSystemPrompt(prompt);
      }
    } catch (_) {}
  }

  Future<void> _expandWindow() async {
    try {
      await _channel.invokeMethod('setFocusable', {'focusable': true});
      await _channel.invokeMethod('setWindowSize', {'width': 280, 'height': 380});
    } catch (_) {}
  }

  Future<void> _shrinkWindow() async {
    try {
      await _channel.invokeMethod('setFocusable', {'focusable': false});
      await _channel.invokeMethod('setWindowSize', {'width': 120, 'height': 120});
    } catch (_) {}
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_isLoading) return; // AI 回复中不自动关闭
    _idleTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) _onClose();
    });
  }

  void _onClose() {
    _summarizeAndSave();
    widget.onClose();
  }

  // ── 发送入口：根据 Feature Flag 分流 ──
  Future<void> _send() async {
    if (_isLoading) return;
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    setState(() => _isLoading = true); // 锁住防止 await 期间重复发送

    final useAgent = await PetFeatureFlags.agentRouting;
    if (useAgent) {
      return _sendViaAgent(text);
    } else {
      return _sendDirect(text);
    }
  }

  // ── 旧路径（完整保留）──
  Future<void> _sendDirect(String userText) async {
    if (_client == null) {
      setState(() {
        _messages.add(_ChatLine(isUser: true, text: userText));
        _messages.add(const _ChatLine(isUser: false, text: '糯糯还没准备好喵~\n请在主应用设置中配置 API Key 后重试'));
      });
      return;
    }
    _inputController.clear();
    _resetIdleTimer();

    setState(() {
      _messages.add(_ChatLine(isUser: true, text: userText));
      _isLoading = true;
    });

    final buffer = StringBuffer();
    final assistantIndex = _messages.length;
    _messages.add(const _ChatLine(isUser: false, text: ''));

    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    // 提取上下文
    final history = <Message>[];
    try {
      final configBox = await Hive.openBox('pet_config');
      final rounds = configBox.get('chatContextRounds', defaultValue: 3) as int;
      final msgCount = (rounds * 2).clamp(0, _messages.length);
      final start = _messages.length - msgCount;
      for (int i = start; i < _messages.length; i++) {
        if (_messages[i].text.isNotEmpty) {
          history.add(Message(
            id: 'ctx_$i',
            role: _messages[i].isUser ? 'user' : 'assistant',
            content: _messages[i].text,
            createdAt: DateTime.now(),
          ));
        }
      }
    } catch (_) {}

    try {
      await for (final chunk in _client!.sendStream(
        history: history,
        userContent: userText,
        thinkingEnabled: false,
        maxTokens: 512,
        cancelToken: _cancelToken,
      )) {
        buffer.write(chunk.text);
        if (mounted) {
          setState(() {
            _messages[assistantIndex] = _ChatLine(isUser: false, text: buffer.toString());
          });
        }
      }
      final aiText = buffer.toString().trim();
      if (aiText.isNotEmpty && mounted) {
        widget.onMemorySave?.call();
        setState(() => _lastFeedbackIndex = assistantIndex);
      }
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel && mounted) {
        setState(() {
          _messages[assistantIndex] = _ChatLine(isUser: false, text: '信号不好喵...待会再试试~');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages[assistantIndex] = _ChatLine(isUser: false, text: '信号不好喵...待会再试试~');
        });
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  // ── 新路径（Agent 通信）──
  Future<void> _sendViaAgent(String userText) async {
    _agentRequestId++;
    final myRequestId = _agentRequestId;
    _inputController.clear();
    _resetIdleTimer();

    // 提取最近历史（先于新消息添加，避免重复发送当前消息）
    final recentHistory = <Map<String, String>>[];
    int rounds = 3;
    try {
      final configBox = await Hive.openBox('pet_config');
      rounds = configBox.get('chatContextRounds', defaultValue: 3) as int;
    } catch (_) {}
    final msgCount = (rounds * 2).clamp(0, _messages.length);
    final start = (_messages.length - msgCount).clamp(0, _messages.length);
    for (int i = start; i < _messages.length; i++) {
      if (_messages[i].isUser || _messages[i].text.isNotEmpty) {
        recentHistory.add({
          'role': _messages[i].isUser ? 'user' : 'assistant',
          'content': _messages[i].text,
        });
      }
    }

    setState(() {
      _messages.add(_ChatLine(isUser: true, text: userText));
      _isLoading = true;
    });

    _messages.add(const _ChatLine(isUser: false, text: ''));
    _agentAssistantIndex = _messages.length - 1;

    _responseTimeout?.cancel();
    _responseTimeout = Timer(const Duration(seconds: 30), () {
      if (mounted && _isLoading && _agentRequestId == myRequestId) {
        setState(() {
          _messages[_agentAssistantIndex] =
              _ChatLine(isUser: false, text: '...糯糯在想该怎么回你喵~');
          _isLoading = false;
        });
      }
    });

    try {
      await _agentChannel.invokeMethod('chatReq', {
        'text': userText,
        'history': recentHistory,
        'requestId': myRequestId,
      });
    } catch (e) {
      _responseTimeout?.cancel();
      if (mounted) {
        // Agent 桥未就绪 → 降级到直接 LLM 路径
        setState(() {
          _messages.removeLast(); // 移除空 assistant 消息
          _messages.removeLast(); // 移除用户消息
          _isLoading = false;
        });
        _sendDirect(userText);
      }
    }
  }

  void _setupAgentHandler() {
    _agentChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'chatChunk':
          final fullText = call.arguments['fullText'] as String? ?? '';
          final requestId = call.arguments['requestId'] as int? ?? 0;
          if (requestId != _agentRequestId) return;
          if (_agentAssistantIndex < 0 || _agentAssistantIndex >= _messages.length) return;
          _responseTimeout?.cancel();
          if (mounted) {
            setState(() {
              _messages[_agentAssistantIndex] =
                  _ChatLine(isUser: false, text: fullText);
            });
            _scrollToBottom();
          }
        case 'chatDone':
          final requestId = call.arguments['requestId'] as int? ?? 0;
          if (requestId != _agentRequestId) return;
          _responseTimeout?.cancel();
          if (mounted) {
            setState(() => _isLoading = false);
            widget.onMemorySave?.call();
            _scrollToBottom();
          }
        case 'chatError':
          final message = call.arguments['message'] as String? ?? '出错了喵...';
          final requestId = call.arguments['requestId'] as int? ?? 0;
          if (requestId != _agentRequestId) return;
          _responseTimeout?.cancel();
          if (mounted) {
            setState(() {
              _messages[_agentAssistantIndex] =
                  _ChatLine(isUser: false, text: message);
              _isLoading = false;
            });
          }
      }
    });
  }

  void _onFeedback(bool liked) {
    if (_lastFeedbackIndex < 0) return;
    final ai = _messages[_lastFeedbackIndex];
    String userText = '';
    for (int i = _lastFeedbackIndex - 1; i >= 0; i--) {
      if (_messages[i].isUser) { userText = _messages[i].text; break; }
    }
    widget.onFeedback?.call(userText, ai.text, liked);
    setState(() => _lastFeedbackIndex = -1);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── 自动 LLM 摘要聊天记忆 ──

  void _summarizeAndSave() {
    if (_aiService == null || _client == null) return;
    final newMsgs = _messages.length - _lastSummarizedIndex;
    if (newMsgs < 4) return; // 至少 2 轮才摘要

    // fire-and-forget，不阻塞 dispose
    _doSummarize();
  }

  Future<void> _doSummarize() async {
    try {
      final svc = PetTokenService();
      if (!await svc.checkBudget()) return;
    } catch (_) {
      return;
    }

    final recent = _messages.sublist(_lastSummarizedIndex);
    final text = recent
        .where((m) => m.text.isNotEmpty)
        .map((m) => '${m.isUser ? "主人" : "糯糯"}: ${m.text}')
        .join('\n');

    if (text.isEmpty) return;

    try {
      final result = await _client!.send(
        history: [],
        userContent: '从以下宠物对话中提取关键信息（用户喜好、宠物状态变化、重要事件），'
            '以 JSON 数组格式返回，不超过 3 条，每条包含 "content" 和 "context" 字段：\n$text',
        maxTokens: 256,
        thinkingEnabled: false,
      );
      _parseSummariesAndSave(result.content);
      _lastSummarizedIndex = _messages.length;
    } catch (e) {
      debugPrint('PetMiniChat._doSummarize failed: $e');
      _lastSummarizedIndex = _messages.length; // 防止重复重试
    }
  }

  void _parseSummariesAndSave(String llmOutput) {
    try {
      final start = llmOutput.indexOf('[');
      final end = llmOutput.lastIndexOf(']');
      if (start == -1 || end == -1) return;
      final sub = llmOutput.substring(start, end + 1);
      final list = (jsonDecode(sub) as List).cast<Map<String, dynamic>>();
      for (final item in list) {
        final content = item['content'] as String?;
        if (content == null || content.isEmpty) continue;
        _aiService!.saveMemory(
          content: content,
          context: (item['context'] as String?) ?? 'pet_chat',
          affectionGain: 3,
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _resetIdleTimer,
      child: Container(
        width: 280,
        height: 380,
        decoration: BoxDecoration(
          color: const Color(0xE6212121),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildMessageList()),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Text('🐾 弗糯糯', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          GestureDetector(
            onTap: _onClose,
            child: const Icon(Icons.close, color: Colors.white38, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final line = _messages[i];
        final showFeedback = widget.onFeedback != null && i == _lastFeedbackIndex && !line.isUser;
        return _buildMessage(line, showFeedback: showFeedback);
      },
    );
  }

  Widget _buildMessage(_ChatLine line, {bool showFeedback = false}) {
    if (line.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 4, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF4A90D9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(line.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
      );
    }
    if (line.text.isEmpty && _isLoading) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A3A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(line.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
          if (showFeedback)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _onFeedback(true),
                    child: const Text('👍', style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _onFeedback(false),
                    child: const Text('👎', style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: '和糯糯说点什么...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                filled: true,
                fillColor: const Color(0xFF4A4A4A),
              ),
              onChanged: (_) => _resetIdleTimer(),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: const Icon(Icons.send, color: Color(0xFF4A90D9), size: 22),
          ),
        ],
      ),
    );
  }
}

class _ChatLine {
  final bool isUser;
  final String text;
  const _ChatLine({required this.isUser, required this.text});
}
