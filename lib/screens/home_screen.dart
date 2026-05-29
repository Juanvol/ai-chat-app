// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/model_config.dart';
import '../services/conversation_service.dart';
import '../services/memory_service.dart';
import '../services/persona_service.dart';
import '../services/feedback_service.dart';
import '../utils/memory_extractor.dart';
import '../utils/export.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input.dart';
import 'settings_screen.dart';
import 'persona_screen.dart';
import 'memory_screen.dart';
import 'feedback_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationService>(
      builder: (context, svc, _) {
        return Scaffold(
          appBar: AppBar(
            leading: Builder(builder: (ctx) => IconButton(icon: const Icon(Icons.menu, size: 22), onPressed: () => Scaffold.of(ctx).openDrawer())),
            title: GestureDetector(
              onTap: svc.currentConversation != null ? () => _showModelSelector(context, svc) : null,
              behavior: HitTestBehavior.opaque,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(svc.currentConversation?.title ?? '', style: C.title),
                if (svc.currentConversation != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_currentModelName(svc), style: C.label),
                    const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFFA0A0AB)),
                  ]),
              ]),
            ),
            actions: [
              if (svc.currentConversation != null) ...[
                IconButton(icon: const Icon(Icons.search, size: 20), tooltip: '搜索对话内容', onPressed: () => _showSearch(context, svc)),
                const SizedBox(width: 0),
                Consumer<FeedbackService>(
                  builder: (_, fb, __) {
                    final active = fb.adjustmentText.isNotEmpty;
                    return IconButton(
                      icon: Stack(children: [
                        Icon(Icons.auto_awesome, size: 18, color: active ? const Color(0xFF7C3AED) : const Color(0xFF888891)),
                        if (fb.hasNewAdjustment)
                          Positioned(top: 0, right: 0, child: Container(width: 7, height: 7, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFEF4444)))),
                      ]),
                      tooltip: active ? 'AI 已根据你的反馈进化' : '反馈',
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FeedbackScreen())),
                    );
                  },
                ),
                IconButton(icon: const Icon(Icons.add_comment_outlined, size: 20), onPressed: svc.createConversation),
              ],
            ],
          ),
          drawer: _Drawer(svc: svc),
          body: svc.currentConversation == null
              ? _Welcome(onTap: (q) { svc.createConversation(); WidgetsBinding.instance.addPostFrameCallback((_) => svc.sendMessage(q)); })
              : _ChatView(conversation: svc.currentConversation!, loading: svc.isLoading,
                  onSend: (t) {
                    final memSvc = context.read<MemoryService>();
                    final perSvc = context.read<PersonaService>();
                    final fbSvc = context.read<FeedbackService>();
                    svc.sendMessage(t,
                      memoryText: memSvc.promptText,
                      personaPrompt: perSvc.selected?.fullPrompt,
                      adjustmentText: fbSvc.adjustmentText,
                      modelId: svc.storage.selModel,
                      maxTokens: svc.globalMaxTokens,
                    );
                  },
                  onStop: () {
                    svc.stopGeneration();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已停止生成'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
        );
      },
    );
  }
}

final _searchJumpNotifier = ValueNotifier<int?>(null);

void _showSearch(BuildContext context, ConversationService svc) {
  final cov = svc.currentConversation;
  if (cov == null) return;
  final ctrl = TextEditingController();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => StatefulBuilder(
        builder: (ctx, setSt) {
          final results = ctrl.text.trim().isEmpty
              ? <({String convId, int msgIndex, String snippet})>[]
              : svc.searchAll(ctrl.text.trim()).where((r) => r.convId == cov.id).toList();
          return Padding(
            padding: const EdgeInsets.all(C.s16),
            child: Column(children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: C.body,
                onChanged: (_) => setSt(() {}),
                decoration: InputDecoration(
                  hintText: '搜索「${cov.title}」的内容...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: ctrl.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () { ctrl.clear(); setSt(() {}); })
                      : null,
                ),
              ),
              const SizedBox(height: C.s12),
              if (ctrl.text.trim().isNotEmpty)
                Text(results.isEmpty ? '无匹配结果' : '共 ${results.length} 条匹配', style: C.caption),
              const SizedBox(height: C.s8),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: results.length,
                  itemBuilder: (_, i) {
                    final r = results[i];
                    return ListTile(
                      dense: true,
                      title: Text(r.snippet, style: C.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.pop(ctx);
                        _searchJumpNotifier.value = r.msgIndex;
                      },
                    );
                  },
                ),
              ),
            ]),
          );
        },
      ),
    ),
  );
}

void _showPersonaSwitcher(BuildContext context, PersonaService ps) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(C.r16))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(C.s16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 32, height: 4, margin: const EdgeInsets.only(bottom: C.s12), decoration: BoxDecoration(color: const Color(0xFFDDDDE5), borderRadius: BorderRadius.circular(2)))),
        Row(children: [
          Text('切换人格', style: C.title),
          const Spacer(),
          TextButton.icon(
            onPressed: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonaScreen())); },
            icon: const Icon(Icons.add, size: 14),
            label: const Text('管理', style: TextStyle(fontSize: 12)),
          ),
        ]),
        const SizedBox(height: C.s8),
        if (ps.personas.isEmpty)
          Padding(
            padding: const EdgeInsets.all(C.s16),
            child: Center(child: Text('暂无可用人格', style: C.caption)),
          )
        else
          ...ps.personas.map((p) {
            final sel = ps.selected?.id == p.id;
            return ListTile(
              leading: Text(p.avatar, style: const TextStyle(fontSize: 22)),
              title: Text(p.name, style: C.body.copyWith(fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
              subtitle: Text(p.mbti.isNotEmpty ? '${p.mbti} · ${p.traits}' : p.traits, style: C.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: sel ? const Icon(Icons.check_circle, size: 18, color: Color(0xFF7C3AED)) : null,
              onTap: () {
                ps.selectAndSave(p.id);
                Navigator.pop(ctx);
              },
            );
          }),
        const SizedBox(height: C.s12),
      ]),
    ),
  );
}

void _showModelSelector(BuildContext context, ConversationService svc) {
  if (svc.isLoading) return;
  final providerOrder = ['deepseek', 'xiaomi', 'openai', 'siliconflow', 'zhipu', 'moonshot', 'custom'];
  final expandedProviders = <String>{providerOrder.firstWhere((p) {
    final cur = ModelConfig.builtIn.where((m) => m.id == svc.storage.selModel).firstOrNull;
    return p == cur?.providerId;
  }, orElse: () => 'deepseek')};

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(C.r16))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.9,
          expand: false,
          builder: (ctx, sc) => ListView(
            controller: sc,
            padding: const EdgeInsets.all(C.s16),
            children: [
              Center(child: Container(width: 32, height: 4, margin: const EdgeInsets.only(bottom: C.s12), decoration: BoxDecoration(color: const Color(0xFFDDDDE5), borderRadius: BorderRadius.circular(2)))),
              Text('选择模型', style: C.title),
              const SizedBox(height: C.s12),
              ...providerOrder.map((pid) {
                final models = ModelConfig.builtIn.where((m) => m.providerId == pid).toList();
                if (models.isEmpty) return const SizedBox.shrink();
                final provider = ModelConfig.providers.where((p) => p.id == pid).firstOrNull;
                final isExpanded = expandedProviders.contains(pid);
                final selId = svc.storage.selModel;
                final hasSelected = models.any((m) => m.id == selId);
                return Container(
                  margin: const EdgeInsets.only(bottom: C.s4),
                  decoration: BoxDecoration(
                    border: Border.all(color: hasSelected ? const Color(0xFFA78BFA).withOpacity(0.5) : const Color(0xFFE5E5E5)),
                    borderRadius: BorderRadius.circular(C.r8),
                  ),
                  child: Column(children: [
                    InkWell(
                      onTap: () => setSt(() => isExpanded ? expandedProviders.remove(pid) : expandedProviders.add(pid)),
                      borderRadius: BorderRadius.vertical(top: const Radius.circular(C.r8), bottom: isExpanded ? Radius.zero : const Radius.circular(C.r8)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(children: [
                          if (hasSelected)
                            Container(width: 6, height: 6, margin: const EdgeInsets.only(right: C.s8),
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFA78BFA))),
                          Text(provider?.name ?? pid, style: hasSelected ? C.body.copyWith(fontWeight: FontWeight.w600) : C.body),
                          const Spacer(),
                          Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 20, color: const Color(0xFF9D9DA8)),
                        ]),
                      ),
                    ),
                    if (isExpanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: Column(children: models.map((m) => RadioListTile<String>(
                          value: m.id, groupValue: selId,
                          onChanged: (v) { svc.setModel(v!); Navigator.pop(ctx); },
                          title: Row(children: [
                            Expanded(child: Text(m.name, style: C.body.copyWith(fontSize: 15))),
                            Text('¥${m.inputPricePerM.toStringAsFixed(m.inputPricePerM == m.inputPricePerM.roundToDouble() ? 0 : 2)} / ¥${m.outputPricePerM.toStringAsFixed(m.outputPricePerM == m.outputPricePerM.roundToDouble() ? 0 : 2)}', style: C.caption),
                          ]),
                          subtitle: Text(m.description, style: C.caption.copyWith(fontSize: 12)),
                          dense: true, visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.only(left: 4),
                        )).toList()),
                      ),
                  ]),
                );
              }),
            ],
          ),
        );
      },
    ),
  );
}

class _Drawer extends StatefulWidget {
  final ConversationService svc;
  const _Drawer({required this.svc});
  @override
  State<_Drawer> createState() => _DrawerState();
}

class _DrawerState extends State<_Drawer> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  List<Conversation> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.svc.conversations;
    final byTitle = widget.svc.conversations.where((c) => c.title.toLowerCase().contains(q)).toList();
    final fullIds = widget.svc.searchAll(q).map((r) => r.convId).toSet();
    final all = <Conversation>[];
    for (final c in widget.svc.conversations) {
      if (byTitle.contains(c) || fullIds.contains(c.id)) all.add(c);
    }
    return all;
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _deleteCov(BuildContext ctx, Conversation c) {
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text('确定删除"${c.title.length > 30 ? '${c.title.substring(0, 30)}...' : c.title}"？\n删除后不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('取消')),
          TextButton(
            onPressed: () { widget.svc.deleteConversation(c.id); Navigator.pop(dCtx); Navigator.pop(ctx); },
            child: const Text('删除', style: TextStyle(color: Color(0xFFE53E3E))),
          ),
        ],
      ),
    );
  }

  void _renameCov(BuildContext ctx, Conversation c) {
    final ctrl = TextEditingController(text: c.title);
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新标题'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) widget.svc.renameConversation(c.id, t);
              Navigator.pop(dCtx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = _filtered;

    return Drawer(
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(C.s20, C.s20, C.s16, C.s16),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(C.r6),
                  color: const Color(0xFFD6E8FB),
                ),
                child: const Center(child: Text('C', style: TextStyle(color: Color(0xFF4A90D9), fontWeight: FontWeight.w700, fontSize: 14))),
              ),
              const SizedBox(width: C.s12),
              Text('AI Chat', style: C.title),
              const Spacer(),
            ]),
          ),

          const SizedBox(height: C.s8),

          // Persona
          Consumer<PersonaService>(
            builder: (_, ps, __) {
              final p = ps.selected;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: C.s12),
                child: InkWell(
                  onTap: () => _showPersonaSwitcher(context, ps),
                  borderRadius: BorderRadius.circular(C.r8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: C.s12, vertical: C.s8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(C.r8),
                      border: Border.all(color: const Color(0xFFDDD6FE)),
                    ),
                    child: Row(children: [
                      Text(p?.avatar ?? '🤖', style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: C.s8),
                      Expanded(
                        child: Text(p?.name ?? '默认助手', style: C.body.copyWith(color: const Color(0xFF6D28D9))),
                      ),
                      Text(p?.mbti ?? '', style: C.label),
                      const SizedBox(width: C.s4),
                      const Icon(Icons.swap_horiz, size: 14, color: Color(0xFFA78BFA)),
                    ]),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: C.s8),

          // New chat
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: C.s12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () { widget.svc.createConversation(); Navigator.pop(context); },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新对话'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.outline),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(C.r8)),
                ),
              ),
            ),
          ),

          const SizedBox(height: C.s8),

          // Search
          if (widget.svc.conversations.length > 3)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: C.s12),
              child: TextField(
                controller: _searchCtrl,
                style: C.body,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: '搜索对话标题和内容...',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFFA0A0AB)),
                  suffixIcon: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () { _searchCtrl.clear(); setState(() => _query = ''); },
                          child: const Icon(Icons.close, size: 14, color: Color(0xFFA0A0AB)),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),

          const SizedBox(height: C.s4),
          const Divider(height: 1),

          // List
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(_query.isNotEmpty ? '无匹配对话' : '暂无对话', style: C.caption))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: C.s4),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      final sel = widget.svc.currentConversation?.id == c.id;
                      return GestureDetector(
                        onTap: () { widget.svc.selectConversation(c.id); Navigator.pop(context); },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: C.s8, vertical: 2),
                          padding: const EdgeInsets.symmetric(horizontal: C.s12, vertical: 10),
                          decoration: BoxDecoration(
                            color: sel ? const Color(0xFFEEF2FF) : Colors.transparent,
                            borderRadius: BorderRadius.circular(C.r8),
                          ),
                          child: Row(children: [
                            Container(width: 4, height: 4,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: sel ? cs.primary : cs.outline)),
                            const SizedBox(width: C.s12),
                            if (c.isPinned)
                              const Padding(
                                padding: EdgeInsets.only(right: C.s4),
                                child: Icon(Icons.push_pin, size: 12, color: Color(0xFFF59E0B)),
                              ),
                            Expanded(child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: sel ? C.body.copyWith(fontWeight: FontWeight.w500) : C.body)),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 14, color: Color(0xFFA0A0AB)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'pin', child: Text(c.isPinned ? '取消置顶' : '置顶', style: C.body)),
                                PopupMenuItem(value: 'rename', child: Text('重命名', style: C.body)),
                                PopupMenuItem(value: 'md', child: Text('导出 Markdown', style: C.body)),
                                PopupMenuItem(value: 'json', child: Text('导出 JSON', style: C.body)),
                                PopupMenuItem(value: 'delete', child: const Text('删除', style: TextStyle(color: Color(0xFFE53E3E), fontSize: 14))),
                              ],
                              onSelected: (v) async {
                                switch (v) {
                                  case 'pin':
                                    widget.svc.togglePin(c.id);
                                    break;
                                  case 'rename':
                                    _renameCov(context, c);
                                    break;
                                  case 'md':
                                    final path = await exportConversation(c, asJson: false);
                                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出: $path')));
                                    break;
                                  case 'json':
                                    final path = await exportConversation(c, asJson: true);
                                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出: $path')));
                                    break;
                                  case 'delete':
                                    _deleteCov(context, c);
                                    break;
                                }
                              },
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),

          const Divider(height: 1),
          _drawerItem(context, Icons.work_outline, '任务上下文', const MemoryScreen()),
          _drawerItem(context, Icons.people_outline, '人格管理', const PersonaScreen()),
          _drawerItem(context, Icons.feedback_outlined, '反馈知识库', const FeedbackScreen()),
          _drawerItem(context, Icons.settings_outlined, '设置', const SettingsScreen()),
          const SizedBox(height: C.s4),
        ]),
      ),
    );
  }
}

String _currentModelName(ConversationService svc) {
  final id = svc.storage.selModel;
  return ModelConfig.builtIn.where((m) => m.id == id).firstOrNull?.name ?? id;
}

Widget _drawerItem(BuildContext context, IconData icon, String label, Widget page) {
  return ListTile(
    dense: true,
    leading: Icon(icon, size: 17, color: const Color(0xFFA0A0AB)),
    title: Text(label, style: C.label),
    onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => page)); },
  );
}

class _Welcome extends StatelessWidget {
  final void Function(String) onTap;
  const _Welcome({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final qs = ['写一个快速排序算法', '帮我写一封商务邮件', '推荐 5 本经典小说', '解释相对论的基本原理'];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: C.s32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 64),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(C.r16),
              color: const Color(0xFFD6E8FB),
            ),
            child: const Icon(Icons.auto_awesome, size: 24, color: Color(0xFF4A90D9)),
          ),
          const SizedBox(height: C.s20),
          Text('AI 助手', style: C.h1),
          const SizedBox(height: C.s8),
          Text('选择任意模型，即刻开始对话', style: C.caption),
          const SizedBox(height: C.s32),
          ...qs.map((q) => GestureDetector(
            onTap: () => onTap(q),
            child: Container(
              margin: const EdgeInsets.only(bottom: C.s8),
              padding: const EdgeInsets.symmetric(horizontal: C.s16, vertical: C.s12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(C.r12),
                border: Border.all(color: const Color(0xFFE8E8EF)),
              ),
              child: Row(children: [
                const Icon(Icons.lightbulb_outline, size: 15, color: Color(0xFF4A90D9)),
                const SizedBox(width: C.s12),
                Expanded(child: Text(q, style: C.body)),
              ]),
            ),
          )),
        ]),
      ),
    );
  }
}

class _ChatView extends StatefulWidget {
  final Conversation conversation;
  final bool loading;
  final void Function(String) onSend;
  final VoidCallback? onStop;
  const _ChatView({required this.conversation, required this.loading, required this.onSend, this.onStop});
  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> with WidgetsBindingObserver {
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
    _searchJumpNotifier.addListener(_onJumpToIndex);
  }

  void _onJumpToIndex() {
    final index = _searchJumpNotifier.value;
    if (index == null) return;
    _searchJumpNotifier.value = null;
    _jumpToMessage(index);
  }

  void _jumpToMessage(int index) {
    if (!_sc.hasClients) return;
    final msgs = widget.conversation.messages;
    if (index < 0 || index >= msgs.length) return;
    final offset = (index * 80.0).clamp(0.0, _sc.position.maxScrollExtent);
    _sc.animateTo(offset, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    setState(() => _highlightedIndex = index);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedIndex = null);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 不取消流式，让生成在后台继续
  }

  void _btm() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients) {
        // 仅当用户在底部附近时才自动滚动，否则不打扰用户阅读
        final atBottom = _sc.position.pixels >= _sc.position.maxScrollExtent - 100;
        if (atBottom) {
          _sc.animateTo(_sc.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      }
    });
  }

  void _showDislikeDialog(BuildContext ctx, String covId, String userMsg, String aiMsg) {
    String reason = '不满意';
    showDialog(
      context: ctx,
      builder: (c) => StatefulBuilder(
        builder: (c, setSt) => AlertDialog(
          title: const Text('记录反馈'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI 回答', style: C.label),
            const SizedBox(height: C.s4),
            Text(aiMsg.length > 120 ? '${aiMsg.substring(0, 120)}...' : aiMsg, style: C.caption),
            const SizedBox(height: C.s16),
            Text('原因', style: C.label),
            const SizedBox(height: C.s8),
            Wrap(spacing: C.s8, runSpacing: C.s8, children: ['不满意', '不准确', '跑题', '太啰嗦', '太简短', '格式差', '语义不明'].map((r) => ChoiceChip(
              label: Text(r, style: const TextStyle(fontSize: 12)),
              selected: reason == r,
              onSelected: (_) => setSt(() => reason = r),
              selectedColor: const Color(0xFFD6E8FB),
            )).toList()),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            ElevatedButton(onPressed: () {
              ctx.read<FeedbackService>().add(
                conversationId: covId,
                userMessage: userMsg,
                aiResponse: aiMsg,
                reason: reason,
              );
              Navigator.pop(c);
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('已记录「$reason」。前往反馈知识库 → AI 分析 可生成修正指令'),
                  duration: const Duration(seconds: 2)),
              );
            }, child: const Text('确认')),
          ],
        ),
      ),
    );
  }

  void _showMessageMenu(BuildContext context, Message msg, int index, Offset globalPosition) {
    if (msg.isStreaming) return;
    final isUser = msg.role == 'user';

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPosition.dx, globalPosition.dy, globalPosition.dx + 1, globalPosition.dy + 1),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('复制')),
        if (!isUser) ...[
          const PopupMenuItem(value: 'regenerate', child: Text('重新生成')),
          const PopupMenuItem(value: 'feedback', child: Text('反馈 / 踩')),
        ],
        if (isUser) const PopupMenuItem(value: 'edit', child: Text('编辑')),
        const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Color(0xFFE53E3E)))),
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      switch (value) {
        case 'copy':
          Clipboard.setData(ClipboardData(text: msg.content));
          ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
        case 'regenerate':
          _doRegenerate();
        case 'feedback':
          final prev = index > 0 ? widget.conversation.messages[index - 1] : null;
          _showDislikeDialog(this.context, widget.conversation.id, prev?.content ?? '', msg.content);
        case 'edit':
          _showEditDialog(msg, index);
        case 'delete':
          _deleteMessage(index);
      }
    });
  }

  void _showEditDialog(Message msg, int index) {
    final ctrl = TextEditingController(text: msg.content);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(controller: ctrl, maxLines: 4, style: C.body,
          decoration: const InputDecoration(hintText: '编辑后重新发送')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          ElevatedButton(onPressed: () {
            Navigator.pop(c);
            final newContent = ctrl.text.trim();
            if (newContent.isEmpty) return;
            final svc = context.read<ConversationService>();
            final cov = svc.currentConversation;
            if (cov == null) return;
            final msgs = cov.messages;
            if (index + 1 < msgs.length && msgs[index + 1].role == 'assistant') {
              msgs.removeAt(index + 1);
            }
            msgs.removeAt(index);
            final memSvc = context.read<MemoryService>();
            final perSvc = context.read<PersonaService>();
            final fbSvc = context.read<FeedbackService>();
            svc.sendMessage(newContent,
              memoryText: memSvc.promptText,
              personaPrompt: perSvc.selected?.fullPrompt,
              adjustmentText: fbSvc.adjustmentText,
              modelId: svc.storage.selModel,
              maxTokens: svc.globalMaxTokens,
            );
          }, child: const Text('发送')),
        ],
      ),
    );
  }

  void _deleteMessage(int index) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('确定删除这条消息？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              final svc = context.read<ConversationService>();
              final cov = svc.currentConversation;
              if (cov == null) return;
              cov.messages.removeAt(index);
              cov.updatedAt = DateTime.now();
              svc.storage.saveConv(cov);
              setState(() {});
            },
            child: const Text('删除', style: TextStyle(color: Color(0xFFE53E3E))),
          ),
        ],
      ),
    );
  }

  void _doRegenerate() {
    if (widget.loading) return;
    final memSvc = context.read<MemoryService>();
    final perSvc = context.read<PersonaService>();
    final fbSvc = context.read<FeedbackService>();
    final svc = context.read<ConversationService>();
    svc.regenerateMessage(
      memoryText: memSvc.promptText,
      personaPrompt: perSvc.selected?.fullPrompt,
      adjustmentText: fbSvc.adjustmentText,
      modelId: svc.storage.selModel,
      maxTokens: svc.globalMaxTokens,
    );
  }

  void _doExtractMemories() async {
    setState(() { _showMemoryBanner = false; _memoryPromptShown = true; });
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final added = await extractMemories(context);
      Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(added > 0 ? '已提取 $added 条上下文' : '未检测到可提取的信息')));
      }
    } catch (e) {
      Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提取失败: $e')));
    }
  }

  @override
  void didUpdateWidget(covariant _ChatView o) {
    super.didUpdateWidget(o);
    _btm();

    if (o.conversation.id != widget.conversation.id) {
      // 保存旧对话的滚动位置
      final svc = context.read<ConversationService>();
      if (o.conversation.id.isNotEmpty && _sc.hasClients) {
        svc.storage.saveConvScroll(o.conversation.id, _sc.position.pixels);
      }
      // 恢复新对话的滚动位置
      final saved = svc.storage.getConvScroll(widget.conversation.id);
      if (saved > 0 && _sc.hasClients) {
        _sc.jumpTo(saved.clamp(0.0, _sc.position.maxScrollExtent));
      }

      _memoryPromptShown = false;
      _feedbackBannerShown = false;
      if (_showMemoryBanner) _showMemoryBanner = false;
      if (_showFeedbackBanner) _showFeedbackBanner = false;
    }

    if (!_feedbackBannerShown && context.read<FeedbackService>().hasNewAdjustment) {
      setState(() => _showFeedbackBanner = true);
    }

    if (o.loading && !widget.loading && !_memoryPromptShown) {
      final count = widget.conversation.messages.where((m) => !m.isStreaming).length;
      if (count >= _memoryThreshold) {
        setState(() => _showMemoryBanner = true);
      }
    }
  }

  @override
  void dispose() {
    _searchJumpNotifier.removeListener(_onJumpToIndex);
    WidgetsBinding.instance.removeObserver(this);
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    if (_showFeedbackBanner)
      Consumer<FeedbackService>(
        builder: (_, fb, __) => Container(
          margin: const EdgeInsets.fromLTRB(C.s16, C.s8, C.s16, 0),
          padding: const EdgeInsets.symmetric(horizontal: C.s12, vertical: C.s8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFEDE9FE), Color(0xFFDDD6FE)]),
            borderRadius: BorderRadius.circular(C.r8),
            border: Border.all(color: const Color(0xFFC4B5FD)),
          ),
          child: Row(children: [
            const Text('✨', style: TextStyle(fontSize: 14)),
            const SizedBox(width: C.s8),
            Expanded(
              child: Text('AI 已根据你的 ${fb.processedCount} 条反馈进化',
                style: C.caption.copyWith(color: const Color(0xFF5B21B6))),
            ),
            GestureDetector(
              onTap: () {
                fb.markAdjustmentSeen();
                Navigator.push(context, MaterialPageRoute(builder: (_) => const FeedbackScreen()));
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: C.s8),
                child: Text('查看', style: TextStyle(fontSize: 13, color: Color(0xFF7C3AED), fontWeight: FontWeight.w500)),
              ),
            ),
            GestureDetector(
              onTap: () { fb.markAdjustmentSeen(); setState(() { _showFeedbackBanner = false; _feedbackBannerShown = true; }); },
              child: const Icon(Icons.close, size: 14, color: Color(0xFF7C3AED)),
            ),
          ]),
        ),
      ),
    if (_showMemoryBanner && !_showFeedbackBanner)
      Container(
        margin: const EdgeInsets.fromLTRB(C.s16, C.s8, C.s16, 0),
        padding: const EdgeInsets.symmetric(horizontal: C.s12, vertical: C.s8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F3FF),
          borderRadius: BorderRadius.circular(C.r8),
          border: Border.all(color: const Color(0xFFDDD6FE)),
        ),
        child: Row(children: [
          const Icon(Icons.auto_awesome, size: 15, color: Color(0xFFA78BFA)),
          const SizedBox(width: C.s8),
          Expanded(
            child: Text('检测到可保存的任务上下文', style: C.caption.copyWith(color: const Color(0xFF7C3AED))),
          ),
          GestureDetector(
            onTap: _doExtractMemories,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: C.s8),
              child: Text('提取', style: TextStyle(fontSize: 13, color: Color(0xFFA78BFA), fontWeight: FontWeight.w500)),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() { _showMemoryBanner = false; _memoryPromptShown = true; }),
            child: const Icon(Icons.close, size: 14, color: Color(0xFFA78BFA)),
          ),
        ]),
      ),
    Expanded(
      child: widget.conversation.messages.isEmpty
          ? Center(child: Text('发送消息开始对话', style: C.caption))
          : ListView.builder(
              controller: _sc,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(top: C.s16, bottom: C.s12),
              itemCount: widget.conversation.messages.length,
              itemBuilder: (_, i) {
                final msg = widget.conversation.messages[i];
                final isAiCompleted = msg.role == 'assistant' && !msg.isStreaming;
                return GestureDetector(
                  onLongPressStart: (details) => _showMessageMenu(context, msg, i, details.globalPosition),
                  child: ChatBubble(
                    key: ValueKey(msg.id),
                    msg: msg,
                    highlighted: i == _highlightedIndex,
                    onDislike: isAiCompleted ? () {
                      final prev = i > 0 ? widget.conversation.messages[i - 1] : null;
                      _showDislikeDialog(context, widget.conversation.id, prev?.content ?? '', msg.content);
                    } : null,
                    onRegenerate: isAiCompleted && !widget.loading ? _doRegenerate : null,
                  ),
                );
              },
            ),
    ),
    ChatInput(loading: widget.loading, onSend: widget.onSend, onStop: widget.onStop),
  ]);
}
