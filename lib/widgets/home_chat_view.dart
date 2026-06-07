// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/conversation.dart';
import '../services/app/conversation_service.dart';
import '../services/app/memory_service.dart';
import '../services/app/persona_service.dart';
import '../services/app/feedback_service.dart';
import 'chat_bubble.dart';
import 'chat_input.dart';
import 'home_chat_banners.dart';
import 'home_chat_dialogs.dart';

final searchJumpNotifier = ValueNotifier<int?>(null);

class HomeChatView extends StatefulWidget {
  final Conversation conversation;
  final bool loading;
  final void Function(String) onSend;
  final VoidCallback? onStop;

  const HomeChatView({
    super.key,
    required this.conversation,
    required this.loading,
    required this.onSend,
    this.onStop,
  });

  @override
  State<HomeChatView> createState() => _HomeChatViewState();
}

class _HomeChatViewState extends State<HomeChatView>
    with WidgetsBindingObserver {
  final _sc = ScrollController();
  bool _showMemoryBanner = false;
  bool _memoryPromptShown = false;
  static const int _memoryThreshold = 10;
  bool _showFeedbackBanner = false;
  bool _feedbackBannerShown = false;
  int? _highlightedIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    searchJumpNotifier.addListener(_onJumpToIndex);
  }

  void _onJumpToIndex() {
    final index = searchJumpNotifier.value;
    if (index == null) return;
    searchJumpNotifier.value = null;
    _jumpToMessage(index);
  }

  void _jumpToMessage(int index) {
    if (!_sc.hasClients) return;
    final msgs = widget.conversation.messages;
    if (index < 0 || index >= msgs.length) return;
    final offset =
        (index * 80.0).clamp(0.0, _sc.position.maxScrollExtent);
    _sc.animateTo(offset,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    setState(() => _highlightedIndex = index);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedIndex = null);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients) {
        final atBottom =
            _sc.position.pixels >= _sc.position.maxScrollExtent - 100;
        if (atBottom) {
          _sc.animateTo(_sc.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut);
        }
      }
    });
  }

  void _doRegenerate() {
    if (widget.loading) return;
    final svc = context.read<ConversationService>();
    final memSvc = context.read<MemoryService>();
    final perSvc = context.read<PersonaService>();
    final fbSvc = context.read<FeedbackService>();
    svc.regenerateMessage(
      memoryText: memSvc.promptText,
      personaPrompt: perSvc.selected?.fullPrompt,
      adjustmentText: fbSvc.adjustmentText,
      modelId: svc.storage.selModel,
      maxTokens: svc.globalMaxTokens,
    );
  }

  void _doExtractMemories() {
    setState(() {
      _showMemoryBanner = false;
      _memoryPromptShown = true;
    });
    HomeChatBanners.doExtractMemories(context);
  }

  @override
  void didUpdateWidget(covariant HomeChatView o) {
    super.didUpdateWidget(o);
    _scrollToBottom();

    if (o.conversation.id != widget.conversation.id) {
      final svc = context.read<ConversationService>();
      if (o.conversation.id.isNotEmpty && _sc.hasClients) {
        svc.storage.saveConvScroll(o.conversation.id, _sc.position.pixels);
      }
      final saved = svc.storage.getConvScroll(widget.conversation.id);
      if (saved > 0 && _sc.hasClients) {
        _sc.jumpTo(saved.clamp(0.0, _sc.position.maxScrollExtent));
      }
      _memoryPromptShown = false;
      _feedbackBannerShown = false;
      if (_showMemoryBanner) _showMemoryBanner = false;
      if (_showFeedbackBanner) _showFeedbackBanner = false;
    }

    if (!_feedbackBannerShown &&
        context.read<FeedbackService>().hasNewAdjustment) {
      setState(() => _showFeedbackBanner = true);
    }

    if (o.loading && !widget.loading && !_memoryPromptShown) {
      final count = widget.conversation.messages
          .where((m) => !m.isStreaming)
          .length;
      if (count >= _memoryThreshold) {
        setState(() => _showMemoryBanner = true);
      }
    }
  }

  @override
  void dispose() {
    searchJumpNotifier.removeListener(_onJumpToIndex);
    WidgetsBinding.instance.removeObserver(this);
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ConversationService>();

    return Column(children: [
      if (_showFeedbackBanner)
        Consumer<FeedbackService>(
          builder: (_, fb, __) => HomeChatBanners.feedbackBanner(context, fb,
              () {
            fb.markAdjustmentSeen();
            setState(() {
              _showFeedbackBanner = false;
              _feedbackBannerShown = true;
            });
          }),
        ),
      if (_showMemoryBanner && !_showFeedbackBanner)
        HomeChatBanners.memoryBanner(
            context, _doExtractMemories, () => setState(() {
                  _showMemoryBanner = false;
                  _memoryPromptShown = true;
                })),
      Expanded(
        child: widget.conversation.messages.isEmpty
            ? Center(child: Text('发送消息开始对话', style: C.caption(context)))
            : ListView.builder(
                controller: _sc,
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(top: C.s16, bottom: C.s12),
                itemCount: widget.conversation.messages.length,
                itemBuilder: (_, i) {
                  final msg = widget.conversation.messages[i];
                  final isAiCompleted =
                      msg.role == 'assistant' && !msg.isStreaming;
                  return GestureDetector(
                    onLongPressStart: (details) =>
                        HomeChatDialogs.showMessageMenu(
                      context,
                      msg,
                      i,
                      details.globalPosition,
                      onRegenerate: _doRegenerate,
                      onDislike: (userMsg, aiMsg) {
                        final prev = i > 0
                            ? widget.conversation.messages[i - 1]
                            : null;
                        HomeChatDialogs.showDislikeDialog(context,
                            widget.conversation.id, prev?.content ?? '', aiMsg);
                      },
                      onEdit: (msg, index) =>
                          HomeChatDialogs.showEditDialog(
                              context, msg, index, svc),
                      onDelete: () => HomeChatDialogs.showDeleteDialog(
                          context, i, svc, () => setState(() {})),
                    ),
                    child: ChatBubble(
                      key: ValueKey(msg.id),
                      msg: msg,
                      highlighted: i == _highlightedIndex,
                      onDislike: isAiCompleted
                          ? () {
                              final prev = i > 0
                                  ? widget.conversation.messages[i - 1]
                                  : null;
                              HomeChatDialogs.showDislikeDialog(
                                  context,
                                  widget.conversation.id,
                                  prev?.content ?? '',
                                  msg.content);
                            }
                          : null,
                      onRegenerate:
                          isAiCompleted && !widget.loading ? _doRegenerate : null,
                    ).animate(key: ValueKey('enter_${msg.id}')).fadeIn(
                        duration: 200.ms,
                        curve: Curves.easeOut).slideY(
                        begin: 0.1,
                        end: 0,
                        duration: 250.ms,
                        curve: Curves.easeOutCubic),
                  );
                },
              ),
      ),
      ChatInput(
          loading: widget.loading,
          onSend: widget.onSend,
          onStop: widget.onStop),
    ]);
  }
}
