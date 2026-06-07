// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/conversation.dart';
import '../services/app/conversation_service.dart';
import '../services/app/persona_service.dart';
import '../services/pet/pet_logger.dart';
import '../services/pet/pet_overlay_host.dart';
import '../services/pet/knowledge/memory/memory_import_service.dart';
import '../utils/export.dart';
import '../utils/page_routes.dart';
import 'home_sheets.dart' show showPersonaSheet;
import '../screens/settings_screen.dart';
import '../screens/persona_screen.dart';
import '../screens/memory_screen.dart';
import '../screens/feedback_screen.dart';
import '../screens/pet/pet_center_screen.dart';

/// 主 App 侧边抽屉 — 对话列表 + 分享给${petOverlayController.petSelfRef}
class HomeDrawer extends StatefulWidget {
  final ConversationService svc;
  const HomeDrawer({super.key, required this.svc});

  @override
  State<HomeDrawer> createState() => HomeDrawerState();
}

class HomeDrawerState extends State<HomeDrawer> {
  String _query = '';
  final _searchCtrl = TextEditingController();
  bool _selectionMode = false;
  final Set<String> _selectedConvIds = {};

  List<Conversation> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.svc.conversations;
    final byTitle = widget.svc.conversations
        .where((c) => c.title.toLowerCase().contains(q))
        .toList();
    final fullIds =
        widget.svc.searchAll(q).map((r) => r.convId).toSet();
    final all = <Conversation>[];
    for (final c in widget.svc.conversations) {
      if (byTitle.contains(c) || fullIds.contains(c.id)) all.add(c);
    }
    return all;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _deleteCov(BuildContext ctx, Conversation c) {
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text(
            '确定删除"${c.title.length > 30 ? '${c.title.substring(0, 30)}...' : c.title}"？\n删除后不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('取消')),
          TextButton(
            onPressed: () {
              widget.svc.deleteConversation(c.id);
              Navigator.pop(dCtx);
              Navigator.pop(ctx);
            },
            child: const Text('删除',
                style: TextStyle(color: Color(0xFFE53E3E))),
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
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('取消')),
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

  Future<void> _shareToPet() async {
    if (_selectedConvIds.isEmpty) return;

    final conversations = <Map<String, dynamic>>[];
    for (final c in widget.svc.conversations) {
      if (!_selectedConvIds.contains(c.id)) continue;
      conversations.add({
        'id': c.id,
        'title': c.title,
        'messages': c.messages
            .where((m) => !m.isStreaming)
            .map((m) => {'role': m.role, 'content': m.content})
            .toList(),
      });
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(strokeWidth: 2),
                const SizedBox(width: 16),
                Text('${petOverlayController.petSelfRef}正在读对话... 📖'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final memoryStore = petOverlayController.knowledgeBase?.memoryStore;
      if (memoryStore == null) {
        throw StateError('MemoryStore 未初始化，请先开启宠物');
      }

      final service = MemoryImportService();
      final result = await service.importFromConversations(
        conversations: conversations,
        memoryStore: memoryStore,
      );

      if (!mounted) return;
      Navigator.pop(context);

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('📝 记忆导入完成'),
          content: Text(
            '${petOverlayController.petSelfRef}从 ${_selectedConvIds.length} 条对话中提取了 ${result.imported.length} 条记忆~\n'
            '${result.skipped > 0 ? '（${result.skipped} 条对话无可提取信息）' : ''}'
            '\n可以在宠物中心 → 🧠 记忆 中查看。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('好的'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().length > 50
              ? '${e.toString().substring(0, 50)}...'
              : e.toString()),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    setState(() {
      _selectionMode = false;
      _selectedConvIds.clear();
    });
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
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(C.r6),
                  color: cs.primaryContainer,
                ),
                child: Center(
                    child: Text('C',
                        style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                            fontSize: 14))),
              ),
              const SizedBox(width: C.s12),
              Text('AI Chat', style: C.title(context)),
              const Spacer(),
              if (widget.svc.conversations.isNotEmpty)
                IconButton(
                  icon: Icon(_selectionMode ? Icons.close : Icons.ios_share,
                      size: 18, color: cs.onSurfaceVariant),
                  tooltip: _selectionMode ? '取消选择' : '分享给${petOverlayController.petSelfRef}',
                  onPressed: () => setState(() {
                    _selectionMode = !_selectionMode;
                    if (!_selectionMode) _selectedConvIds.clear();
                  }),
                ),
            ]),
          ),

          const SizedBox(height: C.s8),

          // Persona switcher
          Consumer<PersonaService>(
            builder: (_, ps, __) {
              final p = ps.selected;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: C.s12),
                child: InkWell(
                  onTap: () => showPersonaSheet(context, ps),
                  borderRadius: BorderRadius.circular(C.r8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: C.s12, vertical: C.s8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(C.r8),
                      border: Border.all(
                          color: cs.primary.withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      Text(p?.avatar ?? '🤖',
                          style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: C.s8),
                      Expanded(
                        child: Text(p?.name ?? '默认助手',
                            style: C.body(context)
                                .copyWith(color: cs.primary)),
                      ),
                      Text(p?.mbti ?? '', style: C.label(context)),
                      const SizedBox(width: C.s4),
                      Icon(Icons.swap_horiz, size: 14, color: cs.primary),
                    ]),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: C.s8),

          // New chat button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: C.s12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  widget.svc.createConversation();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新对话'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.outline),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(C.r8)),
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
                style: C.body(context),
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: '搜索对话标题和内容...',
                  isDense: true,
                  prefixIcon: Icon(Icons.search,
                      size: 16, color: cs.onSurfaceVariant),
                  suffixIcon: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          child: Icon(Icons.close,
                              size: 14, color: cs.onSurfaceVariant),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
              ),
            ),

          const SizedBox(height: C.s4),
          const Divider(height: 1),

          // Conversation list
          Expanded(
            child: AnimatedSwitcher(
              duration: 250.ms,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: list.isEmpty
                  ? Center(
                      key: ValueKey('empty_$_query'),
                      child: Text(_query.isNotEmpty ? '无匹配对话' : '暂无对话',
                          style: C.caption(context)))
                  : ListView.builder(
                      key: const ValueKey('list'),
                      padding: const EdgeInsets.symmetric(vertical: C.s4),
                      physics: const BouncingScrollPhysics(),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final c = list[i];
                        final sel =
                            widget.svc.currentConversation?.id == c.id;
                        return GestureDetector(
                          onTap: () {
                            if (_selectionMode) {
                              setState(() {
                                _selectedConvIds.contains(c.id)
                                    ? _selectedConvIds.remove(c.id)
                                    : _selectedConvIds.add(c.id);
                              });
                            } else {
                              widget.svc.selectConversation(c.id);
                              Navigator.pop(context);
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: C.s8, vertical: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: C.s12, vertical: 10),
                            decoration: BoxDecoration(
                              color: sel
                                  ? cs.primaryContainer
                                      .withValues(alpha: 0.3)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(C.r8),
                            ),
                            child: Row(children: [
                              if (_selectionMode)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(right: C.s8),
                                  child: Icon(
                                    _selectedConvIds.contains(c.id)
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    size: 18,
                                    color: _selectedConvIds.contains(c.id)
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                  ),
                                )
                              else
                                Container(
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: sel
                                            ? cs.primary
                                            : cs.outline)),
                              const SizedBox(width: C.s12),
                              if (c.isPinned)
                                const Padding(
                                  padding: EdgeInsets.only(right: C.s4),
                                  child: Icon(Icons.push_pin,
                                      size: 12,
                                      color: Color(0xFFF59E0B)),
                                ),
                              Expanded(
                                  child: Text(c.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: sel
                                          ? C.body(context).copyWith(
                                              fontWeight: FontWeight.w500)
                                          : C.body(context))),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert,
                                    size: 14, color: cs.onSurfaceVariant),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                      value: 'pin',
                                      child: Text(
                                          c.isPinned ? '取消置顶' : '置顶',
                                          style: C.body(context))),
                                  PopupMenuItem(
                                      value: 'rename',
                                      child: Text('重命名',
                                          style: C.body(context))),
                                  PopupMenuItem(
                                      value: 'md',
                                      child: Text('导出 Markdown',
                                          style: C.body(context))),
                                  PopupMenuItem(
                                      value: 'json',
                                      child: Text('导出 JSON',
                                          style: C.body(context))),
                                  const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除',
                                          style: TextStyle(
                                              color: Color(0xFFE53E3E),
                                              fontSize: 14))),
                                ],
                                onSelected: (v) async {
                                  switch (v) {
                                    case 'pin':
                                      widget.svc.togglePin(c.id);
                                    case 'rename':
                                      _renameCov(context, c);
                                    case 'md':
                                      final path = await exportConversation(
                                          c, asJson: false);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content:
                                                    Text('已导出: $path')));
                                      }
                                    case 'json':
                                      final path = await exportConversation(
                                          c, asJson: true);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content:
                                                    Text('已导出: $path')));
                                      }
                                    case 'delete':
                                      _deleteCov(context, c);
                                  }
                                },
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ),

          // Share button (selection mode)
          if (_selectionMode && _selectedConvIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(C.s12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _shareToPet,
                  icon: const Icon(Icons.pets, size: 18),
                  label: Text('分享 ${_selectedConvIds.length} 条对话给${petOverlayController.petSelfRef}'),
                ),
              ),
            ),
          const Divider(height: 1),
          _drawerItem(context, Icons.work_outline, '任务上下文',
              const MemoryScreen()),
          _drawerItem(context, Icons.people_outline, '人格管理',
              const PersonaScreen()),
          _drawerItem(context, Icons.feedback_outlined, '反馈知识库',
              const FeedbackScreen()),
          _drawerItem(
              context, Icons.pets, '宠物中心', const PetCenterScreen()),
          _drawerItem(context, Icons.settings_outlined, '设置',
              const SettingsScreen()),
          const SizedBox(height: C.s4),
        ]),
      ),
    );
  }
}

Widget _drawerItem(
    BuildContext context, IconData icon, String label, Widget page) {
  return ListTile(
    dense: true,
    leading: Hero(
        tag: 'hero_icon_$label',
        child: Icon(icon,
            size: 17,
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
    title: Hero(
        tag: 'hero_title_$label',
        child: Text(label, style: C.label(context))),
    onTap: () {
      PetLogger().info('Home', 'navigate: $label');
      Navigator.pop(context);
      pushElastic(context, page);
    },
  );
}
