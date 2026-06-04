// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../services/pet/pet_agent_core.dart';
import '../../services/pet/pet_chat_service.dart';
import '../../services/pet/pet_logger.dart';
import '../../services/pet/pet_token_service.dart';
import '../../services/pet/pet_profile_service.dart';
import '../../models/model_config.dart';
import 'pet_chat_history_screen.dart';

class PetChatScreen extends StatefulWidget {
  const PetChatScreen({super.key});

  @override
  State<PetChatScreen> createState() => _PetChatScreenState();
}

class _PetChatScreenState extends State<PetChatScreen> {
  final _inputController = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final _scrollController = ScrollController();
  bool _isLoading = false;

  final PetChatService _chatService = PetChatService();
  String? _chatId;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    await _chatService.init();
    // 创建或恢复最近的会话
    String? chatId = _chatService.currentId;
    if (chatId != null) {
      final chat = await _chatService.getChat(chatId);
      if (chat != null) {
        final rawMsgs = chat['messages'] as List? ?? [];
        final msgs = rawMsgs
            .map((m) => Map<String, String>.from({
                  'role': '${m['role'] ?? ''}',
                  'content': '${m['content'] ?? ''}',
                }))
            .toList();
        setState(() {
          _chatId = chatId;
          _messages.addAll(msgs);
        });
        _scrollToBottom();
        return;
      }
    }
    // 无历史 → 创建新会话
    chatId = await _chatService.createChat();
    setState(() => _chatId = chatId);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;
    _inputController.clear();

    // 懒初始化 Agent
    if (PetAgentCore.shared == null) {
      await _initAgent();
    }

    final agent = PetAgentCore.shared;
    if (agent == null) {
      _addMessage('assistant', '雪乃还在睡觉喵...请先在设置中配置 API Key~');
      return;
    }

    // 确保有会话
    if (_chatId == null) {
      _chatId = await _chatService.createChat();
    }

    // 持久化用户消息
    await _chatService.addMessage(_chatId!, 'user', text);

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _messages.add({'role': 'assistant', 'content': ''});
      _isLoading = true;
    });
    _scrollToBottom();

    final aiIndex = _messages.length - 1;
    final history = _buildHistory();

    await agent.chatStream(
      userText: text,
      history: history,
      onChunk: (fullText) {
        if (!mounted) return;
        setState(() {
          _messages[aiIndex]['content'] = fullText;
        });
        _scrollToBottom();
      },
      onDone: () async {
        if (!mounted) return;
        setState(() => _isLoading = false);
        // 持久化 AI 回复
        final aiText = _messages[aiIndex]['content'] ?? '';
        if (aiText.isNotEmpty && _chatId != null) {
          await _chatService.addMessage(_chatId!, 'assistant', aiText);
        }
        PetLogger().info('PetChat', 'chat done, ${_messages.length} msgs');
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _messages[aiIndex]['content'] = error;
          _isLoading = false;
        });
        PetLogger().warn('PetChat', 'chat error: $error');
      },
    );
  }

  List<Map<String, dynamic>> _buildHistory() {
    final history = <Map<String, dynamic>>[];
    final end = _messages.length - 1;
    for (int i = end - 1; i >= 1; i -= 2) {
      if (i - 1 >= 0 &&
          _messages[i - 1]['role'] == 'user' &&
          _messages[i]['role'] == 'assistant' &&
          (_messages[i]['content']?.isNotEmpty == true)) {
        history.insert(0, {
          'role': 'user',
          'content': _messages[i - 1]['content'],
        });
        history.insert(0, {
          'role': 'assistant',
          'content': _messages[i]['content'],
        });
      }
      if (history.length >= 6) break;
    }
    return history;
  }

  Future<void> _initAgent() async {
    try {
      final settingsBox = await Hive.openBox('settings');
      final petConfigBox = await Hive.openBox('pet_config');

      final modelId = petConfigBox.get('chatModel') as String? ?? 'deepseek-chat';
      final modelInfo = ModelConfig.resolveModel(modelId);
      final providerId = modelInfo?.providerId ?? 'deepseek';

      final apiKey = settingsBox.get('${providerId}_key') as String?
          ?? settingsBox.get('api_key') as String?;

      if (apiKey == null || apiKey.isEmpty) {
        PetLogger().warn('PetChat', '_initAgent failed: no API key for provider=$providerId');
        return;
      }

      final agent = PetAgentCore(
        tokenService: PetTokenService.instance,
        profileService: PetProfileService(),
      );
      await agent.init(decisionApiKey: apiKey, chatApiKey: apiKey);
      agent.start();
      PetLogger().info('PetChat', 'Agent 懒初始化完成, provider=$providerId model=$modelId');
    } catch (e) {
      PetLogger().error('PetChat', '_initAgent failed', e);
    }
  }

  void _addMessage(String role, String content) {
    setState(() => _messages.add({'role': role, 'content': content}));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 打开聊天记录页面
  Future<void> _openHistory() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PetChatHistoryScreen(
          chatService: _chatService,
          currentChatId: _chatId,
        ),
      ),
    );
    // 用户选择了某个历史会话 → 加载它
    if (result != null && result != _chatId) {
      await _loadChat(result);
    }
  }

  Future<void> _loadChat(String chatId) async {
    final chat = await _chatService.getChat(chatId);
    if (chat == null) return;
    final rawMsgs = chat['messages'] as List? ?? [];
    final msgs = rawMsgs
        .map((m) => Map<String, String>.from({
              'role': '${m['role'] ?? ''}',
              'content': '${m['content'] ?? ''}',
            }))
        .toList();
    await _chatService.switchChat(chatId);
    setState(() {
      _chatId = chatId;
      _messages.clear();
      _messages.addAll(msgs);
    });
    _scrollToBottom();
  }

  /// 新建对话
  Future<void> _newChat() async {
    final newId = await _chatService.createChat();
    setState(() {
      _chatId = newId;
      _messages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('和雪乃聊天'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, size: 20),
            tooltip: '新建对话',
            onPressed: _newChat,
          ),
          IconButton(
            icon: const Icon(Icons.history, size: 20),
            tooltip: '聊天记录',
            onPressed: _openHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text('开始和雪乃聊天吧~',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _MessageBubble(
                      msg: _messages[i],
                      isLoading: _isLoading &&
                          i == _messages.length - 1 &&
                          _messages[i]['content'] == '',
                    ),
                  ),
          ),
          _buildInputBar(cs),
        ],
      ),
    );
  }

  Widget _buildInputBar(ColorScheme cs) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                decoration: InputDecoration(
                  hintText: '和雪乃说点什么...',
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                ),
                style: TextStyle(color: cs.onSurface),
                maxLines: 3,
                minLines: 1,
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.send, color: cs.primary),
              onPressed: _isLoading ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, String> msg;
  final bool isLoading;
  const _MessageBubble({required this.msg, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    final isUser = msg['role'] == 'user';
    final content = msg['content'] ?? '';
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? cs.primary.withValues(alpha: 0.1)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: isLoading && content.isEmpty
            ? const SizedBox(
                width: 24,
                height: 16,
                child: Center(
                    child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2))))
            : Text(content,
                style: TextStyle(fontSize: 15, color: cs.onSurface)),
      ),
    );
  }
}
