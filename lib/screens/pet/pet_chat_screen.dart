// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../services/pet/pet_agent_core.dart';
import '../../services/pet/pet_logger.dart';
import '../../services/pet/pet_token_service.dart';
import '../../services/pet/pet_profile_service.dart';
import '../../models/model_config.dart';

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

    // 懒初始化 Agent（如果尚未初始化）
    if (PetAgentCore.shared == null) {
      await _initAgent();
    }

    final agent = PetAgentCore.shared;
    if (agent == null) {
      _addMessage('assistant', '糯糯还在睡觉喵...请先在设置中配置 API Key~');
      return;
    }

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
      onDone: () {
        if (!mounted) return;
        setState(() => _isLoading = false);
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
    // 取最近 N 轮对话作为上下文（排除当前轮和空回复）
    final history = <Map<String, dynamic>>[];
    final end = _messages.length - 1; // 排除刚加的 user+assistant
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
      if (history.length >= 6) break; // 最多 3 轮
    }
    return history;
  }

  /// 懒初始化 PetAgentCore（当 shared 尚未由 main.dart 或 PetAiService 初始化时）
  Future<void> _initAgent() async {
    try {
      final settingsBox = await Hive.openBox('settings');
      final petConfigBox = await Hive.openBox('pet_config');

      // 1. 读取用户在宠物设置中选择的模型
      final modelId = petConfigBox.get('chatModel') as String? ?? 'deepseek-chat';
      final modelInfo = ModelConfig.resolveModel(modelId);
      final providerId = modelInfo?.providerId ?? 'deepseek';

      // 2. 读取对应 provider 的 API Key（优先 provider 专属 key，fallback 主 api_key）
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text('开始和糯糯聊天吧~',
                        style: TextStyle(color: Colors.grey)),
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
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                decoration: const InputDecoration(
                  hintText: '和糯糯说点什么...',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
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
                  : const Icon(Icons.send),
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
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.1)
              : Colors.grey.shade100,
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
            : Text(content, style: const TextStyle(fontSize: 15)),
      ),
    );
  }
}
