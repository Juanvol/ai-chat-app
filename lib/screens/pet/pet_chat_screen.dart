// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../../services/pet/pet_agent_core.dart';
import '../../services/pet/pet_chat_service.dart';
import '../../services/pet/pet_overlay_host.dart';
import '../../services/pet/pet_logger.dart';
import 'pet_chat_history_screen.dart';

class PetChatScreen extends StatefulWidget {
  const PetChatScreen({super.key});

  @override
  State<PetChatScreen> createState() => _PetChatScreenState();
}

class _PetChatScreenState extends State<PetChatScreen> {
  final _inputController = TextEditingController();

  String get _petName {
    final n = petOverlayController.personaStore?.persona.name;
    return (n != null && n.isNotEmpty) ? n : '糯糯';
  }
  final List<Map<String, String>> _messages = [];
  final _scrollController = ScrollController();
  bool _isLoading = false;

  final PetChatService _chatService = PetChatService();
  String? _chatId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initChat());
  }

  Future<void> _initChat() async {
    await _chatService.init();
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
        if (!mounted) return;
        setState(() {
          _chatId = chatId;
          _messages.addAll(msgs);
        });
        _scrollToBottom();
        return;
      }
    }
    chatId = await _chatService.createChat();
    if (mounted) setState(() => _chatId = chatId);
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

    try {
      if (PetAgentCore.shared == null) {
        await _initAgent();
      }

      final agent = PetAgentCore.shared;
      if (agent == null) {
        final name = _petName;
        _addMessage('assistant', '$name还在睡觉喵...请先在设置中配置 API Key~');
        return;
      }

      _chatId ??= await _chatService.createChat();

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
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _addMessage('assistant', '发送失败，请稍后再试~');
      PetLogger().error('PetChat', '_send failed', e);
    }
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
    await PetAgentCore.ensureInitialized();
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
    if (result != null && result != _chatId && mounted) {
      await _loadChat(result);
    }
  }

  Future<void> _loadChat(String chatId) async {
    try {
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
      if (!mounted) return;
      setState(() {
        _chatId = chatId;
        _messages.clear();
        _messages.addAll(msgs);
      });
      _scrollToBottom();
    } catch (_) {}
  }

  /// 新建对话
  Future<void> _newChat() async {
    try {
      final newId = await _chatService.createChat();
      if (!mounted) return;
      setState(() {
        _chatId = newId;
        _messages.clear();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('和$_petName聊天'),
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
                    child: Text('开始和$_petName聊天吧~',
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
                  hintText: '和$_petName说点什么...',
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
