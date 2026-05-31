import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'c:\Users\lenovo\Desktop\ai-chat-app\lib\pet\mini_chat.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add import
content = content.replace(
    "import '../api/deepseek_client.dart';",
    "import '../api/deepseek_client.dart';\nimport '../services/pet_feature_flags.dart';"
)

# 2. Add _agentChannel
content = content.replace(
    "static const _channel = MethodChannel('com.example.deepseek_chat/pet_window');",
    "static const _channel = MethodChannel('com.example.deepseek_chat/pet_window');\n  static const _agentChannel = MethodChannel('com.example.deepseek_chat/pet_agent_bridge');"
)

# 3. Add agent fields
content = content.replace(
    "int _lastFeedbackIndex = -1;",
    "int _lastFeedbackIndex = -1;\n  int _agentRequestId = 0;\n  Timer? _responseTimeout;\n  int _agentAssistantIndex = -1;"
)

# 4. Add _setupAgentHandler() call at end of initState
content = content.replace(
    "_resetIdleTimer();\n  }",
    "_resetIdleTimer();\n    _setupAgentHandler();\n  }"
)

# 5. Replace _send() with split version
# Find the start of _send()
old_start = "  Future<void> _send() async {"
old_end = "  void _onFeedback(bool liked) {"

start_idx = content.find(old_start)
end_idx = content.find(old_end)
assert start_idx != -1, "Cannot find _send()"
assert end_idx != -1, "Cannot find _onFeedback()"
assert start_idx < end_idx, "_send() must be before _onFeedback()"

old_send = content[start_idx:end_idx]

new_send = """  // ── 发送入口：根据 Feature Flag 分流 ──
  Future<void> _send() async {
    if (_isLoading) return;
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    final useAgent = await PetFeatureFlags.agentRouting;
    if (useAgent) {
      return _sendViaAgent(text);
    } else {
      return _sendDirect(text);
    }
  }

  // ── 旧路径（完整保留）──
  Future<void> _sendDirect(String userText) async {
    if (_client == null) return;
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

    try {
      await for (final chunk in _client!.sendStream(
        history: [],
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
    } on DioException catch (_) {
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

    setState(() {
      _messages.add(_ChatLine(isUser: true, text: userText));
      _isLoading = true;
    });

    _agentAssistantIndex = _messages.length;
    _messages.add(const _ChatLine(isUser: false, text: ''));

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

    final recentHistory = <Map<String, String>>[];
    final start = (_messages.length - 6).clamp(0, _messages.length);
    for (int i = start; i < _messages.length; i++) {
      if (_messages[i].isUser || _messages[i].text.isNotEmpty) {
        recentHistory.add({
          'role': _messages[i].isUser ? 'user' : 'assistant',
          'content': _messages[i].text,
        });
      }
    }

    try {
      await _agentChannel.invokeMethod('chatReq', {
        'text': userText,
        'history': recentHistory,
        'requestId': myRequestId,
      });
    } catch (e) {
      _responseTimeout?.cancel();
      if (mounted) {
        setState(() {
          _messages[_agentAssistantIndex] =
              _ChatLine(isUser: false, text: '糯糯在睡觉喵~打开 App 唤醒她 💤');
          _isLoading = false;
        });
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

"""

content = content[:start_idx] + new_send + content[end_idx:]

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('mini_chat.dart updated OK')
