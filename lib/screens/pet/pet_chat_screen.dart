// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../../services/pet/pet_agent_core.dart';
import '../../services/pet/pet_chat_service.dart';
import '../../services/pet/pet_logger.dart';
import '../../services/pet/popup_chat_service.dart';
import 'pet_chat_history_screen.dart';

class PetChatScreen extends StatefulWidget {
  const PetChatScreen({super.key});

  @override
  State<PetChatScreen> createState() => _PetChatScreenState();
}

class _PetChatScreenState extends State<PetChatScreen> {
  // ── 分类：0=宠物聊天, 1=弹窗聊天 ──
  int _category = 0;

  // ═══════════════════════════════════════════
  // 宠物聊天（Hive 持久化）
  // ═══════════════════════════════════════════
  final _inputController = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final _scrollController = ScrollController();
  bool _isLoading = false;
  final PetChatService _chatService = PetChatService();
  String? _chatId;

  // ═══════════════════════════════════════════
  // 弹窗聊天（SharedPreferences 持久化）
  // ═══════════════════════════════════════════
  final _popupSvc = PopupChatService();
  List<PopupSession> _popupSessions = [];
  String? _activePopupId;
  List<Map<String, dynamic>> _popupMessages = [];
  final _popupInputCtrl = TextEditingController();
  final _popupScrollCtrl = ScrollController();
  bool _popupLoading = false;
  bool _popupSessionsLoading = true;
  int _popupAiIdx = -1;

  @override
  void initState() {
    super.initState();
    _initChat();
    _loadPopupSessions();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _popupInputCtrl.dispose();
    _popupScrollCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════
  // 宠物聊天逻辑（不变）
  // ═══════════════════════════════════════════

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

  Future<void> _sendPet() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;
    _inputController.clear();

    if (PetAgentCore.shared == null) {
      await _initAgent();
    }

    final agent = PetAgentCore.shared;
    if (agent == null) {
      _addMessage('assistant', '雪乃还在睡觉喵...请先在设置中配置 API Key~');
      return;
    }

    if (_chatId == null) {
      _chatId = await _chatService.createChat();
    }

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
  }

  List<Map<String, dynamic>> _buildHistory() {
    final history = <Map<String, dynamic>>[];
    final end = _messages.length - 1;
    for (int i = end - 1; i >= 1; i -= 2) {
      if (i - 1 >= 0 &&
          _messages[i - 1]['role'] == 'user' &&
          _messages[i]['role'] == 'assistant' &&
          (_messages[i]['content']?.isNotEmpty == true)) {
        history.insert(0, {'role': 'user', 'content': _messages[i - 1]['content']});
        history.insert(0, {'role': 'assistant', 'content': _messages[i]['content']});
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
  }

  Future<void> _newChat() async {
    final newId = await _chatService.createChat();
    if (!mounted) return;
    setState(() {
      _chatId = newId;
      _messages.clear();
    });
  }

  // ═══════════════════════════════════════════
  // 弹窗聊天逻辑（新）
  // ═══════════════════════════════════════════

  Future<void> _loadPopupSessions() async {
    final sessions = await _popupSvc.listSessions();
    if (!mounted) return;
    setState(() {
      _popupSessions = sessions;
      _popupSessionsLoading = false;
    });
    // 自动选中第一个会话
    if (sessions.isNotEmpty && _activePopupId == null) {
      _switchPopupSession(sessions.first.id);
    }
  }

  Future<void> _switchPopupSession(String sessionId) async {
    await _popupSvc.switchSession(sessionId);
    final msgs = await _popupSvc.getSessionMessages(sessionId);
    if (!mounted) return;
    setState(() {
      _activePopupId = sessionId;
      _popupMessages = msgs;
    });
    _popupScrollToBottom();
  }

  Future<void> _newPopupSession() async {
    final newId = await _popupSvc.createSession();
    if (newId != null && mounted) {
      await _loadPopupSessions();
      _switchPopupSession(newId);
    }
  }

  Future<void> _deletePopupSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除弹窗对话'),
        content: const Text('确定要删除这条弹窗聊天记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _popupSvc.deleteSession(sessionId);
    if (!mounted) return;
    // 如果删除的是当前会话，清空视图
    if (sessionId == _activePopupId) {
      setState(() {
        _activePopupId = null;
        _popupMessages.clear();
      });
    }
    await _loadPopupSessions();
  }

  Future<void> _sendPopup() async {
    if (_popupLoading) return;
    final text = _popupInputCtrl.text.trim();
    if (text.isEmpty) return;

    // 确保有会话
    if (_activePopupId == null) {
      await _newPopupSession();
    }
    if (_activePopupId == null) return;

    // 确保 Agent 就绪
    if (PetAgentCore.shared == null) {
      await _initAgent();
    }
    final agent = PetAgentCore.shared;
    if (agent == null) {
      setState(() {
        _popupMessages.add({'isUser': false, 'text': '雪乃还在睡觉喵...请先在设置中配置 API Key~'});
      });
      return;
    }

    final sessionId = _activePopupId!;
    _popupInputCtrl.clear();

    // 持久化用户消息 → SharedPreferences
    await _popupSvc.saveMessage(sessionId, isUser: true, text: text);

    setState(() {
      _popupMessages.add({'isUser': true, 'text': text});
      _popupMessages.add({'isUser': false, 'text': ''});
      _popupLoading = true;
      _popupAiIdx = _popupMessages.length - 1;
    });
    _popupScrollToBottom();

    // 构建历史上下文
    final history = <Map<String, dynamic>>[];
    for (int i = 0; i < _popupMessages.length - 2; i++) {
      final m = _popupMessages[i];
      final content = m['text'] as String? ?? '';
      if (content.isNotEmpty) {
        history.add({
          'role': (m['isUser'] == true) ? 'user' : 'assistant',
          'content': content,
        });
      }
    }

    await agent.chatStream(
      userText: text,
      history: history,
      onChunk: (fullText) {
        if (!mounted) return;
        setState(() {
          if (_popupAiIdx >= 0 && _popupAiIdx < _popupMessages.length) {
            _popupMessages[_popupAiIdx]['text'] = fullText;
          }
        });
        _popupScrollToBottom();
      },
      onDone: () async {
        if (!mounted) return;
        setState(() => _popupLoading = false);
        // 持久化 AI 回复 → SharedPreferences
        final aiText = (_popupAiIdx >= 0 && _popupAiIdx < _popupMessages.length)
            ? (_popupMessages[_popupAiIdx]['text'] as String? ?? '')
            : '';
        if (aiText.isNotEmpty) {
          await _popupSvc.saveMessage(sessionId, isUser: false, text: aiText);
        }
        // 刷新会话列表（标题/消息计数更新）
        _loadPopupSessions();
        PetLogger().info('PetChat', 'popup chat done');
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          if (_popupAiIdx >= 0 && _popupAiIdx < _popupMessages.length) {
            _popupMessages[_popupAiIdx]['text'] = error;
          }
          _popupLoading = false;
        });
        PetLogger().warn('PetChat', 'popup chat error: $error');
      },
    );
  }

  void _popupScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_popupScrollCtrl.hasClients) {
        _popupScrollCtrl.animateTo(
          _popupScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ═══════════════════════════════════════════
  // 主 build
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildCategoryToggle(),
        Expanded(
          child: _category == 0 ? _buildPetChat() : _buildPopupChat(),
        ),
      ],
    );
  }

  Widget _buildCategoryToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('宠物聊天'), icon: Icon(Icons.pets, size: 18)),
            ButtonSegment(value: 1, label: Text('弹窗聊天'), icon: Icon(Icons.chat_bubble_outline, size: 18)),
          ],
          selected: {_category},
          onSelectionChanged: (v) => setState(() => _category = v.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13)),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 宠物聊天 UI
  // ═══════════════════════════════════════════

  Widget _buildPetChat() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('和雪乃聊天'),
        centerTitle: true,
        toolbarHeight: 44,
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
          _buildPetInputBar(cs),
        ],
      ),
    );
  }

  Widget _buildPetInputBar(ColorScheme cs) {
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                ),
                style: TextStyle(color: cs.onSurface),
                maxLines: 3,
                minLines: 1,
                onSubmitted: (_) => _sendPet(),
              ),
            ),
            IconButton(
              icon: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.send, color: cs.primary),
              onPressed: _isLoading ? null : _sendPet,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 弹窗聊天 UI
  // ═══════════════════════════════════════════

  Widget _buildPopupChat() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('弹窗聊天'),
        centerTitle: true,
        toolbarHeight: 44,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, size: 20),
            tooltip: '新建弹窗对话',
            onPressed: _newPopupSession,
          ),
        ],
      ),
      body: Column(
        children: [
          // 会话选择器
          _buildPopupSessionBar(cs),
          const Divider(height: 1),
          // 消息列表
          Expanded(
            child: _popupSessionsLoading
                ? const Center(child: CircularProgressIndicator())
                : _activePopupId == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 48,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text('暂无弹窗聊天', style: TextStyle(color: cs.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            TextButton.icon(
                              onPressed: _newPopupSession,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('新建弹窗对话'),
                            ),
                          ],
                        ),
                      )
                    : _popupMessages.isEmpty
                        ? Center(
                            child: Text('开始聊天吧~ 💬',
                                style: TextStyle(color: cs.onSurfaceVariant)),
                          )
                        : ListView.builder(
                            controller: _popupScrollCtrl,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            itemCount: _popupMessages.length,
                            itemBuilder: (context, i) {
                              final m = _popupMessages[i];
                              final isUser = m['isUser'] == true;
                              final text = m['text'] as String? ?? '';
                              final isLoading = _popupLoading &&
                                  i == _popupMessages.length - 1 &&
                                  text.isEmpty;
                              return _MessageBubble(
                                msg: {'role': isUser ? 'user' : 'assistant', 'content': text},
                                isLoading: isLoading,
                              );
                            },
                          ),
          ),
          // 输入栏
          _buildPopupInputBar(cs),
        ],
      ),
    );
  }

  Widget _buildPopupSessionBar(ColorScheme cs) {
    if (_popupSessions.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: _popupSessions.length + 1, // +1 for "+" button
        itemBuilder: (context, i) {
          if (i >= _popupSessions.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('新建'),
                visualDensity: VisualDensity.compact,
                onPressed: _newPopupSession,
              ),
            );
          }
          final session = _popupSessions[i];
          final isActive = session.id == _activePopupId;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InputChip(
              label: Text(
                session.title.length > 12
                    ? '${session.title.substring(0, 12)}...'
                    : session.title,
                style: TextStyle(fontSize: 12),
              ),
              selected: isActive,
              visualDensity: VisualDensity.compact,
              onPressed: () => _switchPopupSession(session.id),
              onDeleted: () => _deletePopupSession(session.id),
              deleteIcon: const Icon(Icons.close, size: 14),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPopupInputBar(ColorScheme cs) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _popupInputCtrl,
                decoration: InputDecoration(
                  hintText: _activePopupId == null ? '先新建一个弹窗对话...' : '输入消息...',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                ),
                style: TextStyle(color: cs.onSurface),
                maxLines: 3,
                minLines: 1,
                enabled: _activePopupId != null,
                onSubmitted: (_) => _sendPopup(),
              ),
            ),
            IconButton(
              icon: _popupLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.send, color: cs.primary),
              onPressed: _popupLoading || _activePopupId == null ? null : _sendPopup,
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
          color: isUser ? cs.primary.withValues(alpha: 0.1) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: isLoading && content.isEmpty
            ? const SizedBox(width: 24, height: 16, child: Center(child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))))
            : Text(content, style: TextStyle(fontSize: 15, color: cs.onSurface)),
      ),
    );
  }
}
