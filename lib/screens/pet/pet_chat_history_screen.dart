// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../../services/pet/pet_chat_service.dart';
import '../../services/pet/popup_chat_service.dart';

/// 聊天记录管理 — 折叠面板：宠物聊天 + 弹窗聊天
class PetChatHistoryScreen extends StatefulWidget {
  final PetChatService chatService;
  final String? currentChatId;

  const PetChatHistoryScreen({
    super.key,
    required this.chatService,
    this.currentChatId,
  });

  @override
  State<PetChatHistoryScreen> createState() => _PetChatHistoryScreenState();
}

class _PetChatHistoryScreenState extends State<PetChatHistoryScreen> {
  final _popupSvc = PopupChatService();

  List<Map<String, dynamic>> _petChats = [];
  List<PopupSession> _popupSessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final petChats = await widget.chatService.listChats();
    final popupSessions = await _popupSvc.listSessions();
    if (!mounted) return;
    setState(() {
      _petChats = petChats;
      _popupSessions = popupSessions;
      _loading = false;
    });
  }

  Future<void> _deletePetChat(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话'),
        content: const Text('确定要删除这条宠物聊天记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.chatService.deleteChat(id);
    _loadAll();
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
    _loadAll();
  }

  Future<void> _clearAllPopupSessions() async {
    // 逐个清除所有弹窗会话
    for (final s in _popupSessions) {
      await _popupSvc.deleteSession(s.id);
    }
    _loadAll();
  }

  Future<void> _newPetChat() async {
    final newId = await widget.chatService.createChat();
    if (!mounted) return;
    await _loadAll();
    // 创建后切换到新会话
    if (mounted) Navigator.pop(context, newId);
  }

  Future<void> _newPopupSession() async {
    final newId = await _popupSvc.createSession();
    if (newId != null && mounted) {
      await _loadAll();
    }
  }

  /// 弹窗会话被选中 → 切换活跃会话
  Future<void> _onPopupSessionTap(PopupSession session) async {
    await _popupSvc.switchSession(session.id);
    if (mounted) await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天记录'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _petChats.isEmpty && _popupSessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text('暂无聊天记录', style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text('去和雪乃聊聊天吧~', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                    ],
                  ),
                )
              : _buildPanels(cs),
    );
  }

  Widget _buildPanels(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // ── 宠物聊天 ──
        _SessionPanel(
          title: '宠物聊天',
          count: _petChats.length,
          sessions: _petChats.map((chat) => _SessionItem(
            id: chat['id'] as String? ?? '',
            title: chat['title'] as String? ?? '新对话',
            subtitle: _buildPetPreview(chat),
            updatedAt: chat['updatedAt'] as String?,
            isActive: chat['id'] == widget.currentChatId,
          )).toList(),
          onNew: _newPetChat,
          onTap: (id) => Navigator.pop(context, id), // 返回选中 ID → PetChatScreen 切换
          onDelete: _deletePetChat,
          trailingBuilder: null,
        ),
        // ── 弹窗聊天（始终显示）──
        const SizedBox(height: 8),
        _SessionPanel(
          title: '弹窗聊天',
          count: _popupSessions.length,
          sessions: _popupSessions.map((s) => _SessionItem(
              id: s.id,
              title: s.title,
              subtitle: '${s.msgCount} 条消息',
              updatedAt: _formatTimeMs(s.createdAt.millisecondsSinceEpoch),
              isActive: _popupSessions.isNotEmpty && _popupSessions.first.id == s.id,
            )).toList(),
            onNew: _newPopupSession,
            onTap: (id) {
              final s = _popupSessions.firstWhere((s) => s.id == id, orElse: () => _popupSessions.first);
              _onPopupSessionTap(s);
            },
            onDelete: _deletePopupSession,
            trailingBuilder: _popupSessions.isNotEmpty ? (id) => _buildClearAllButton() : null,
          ),
      ],
    );
  }

  Widget? _buildClearAllButton() {
    return TextButton.icon(
      onPressed: _popupSessions.isEmpty ? null : _clearAllPopupSessions,
      icon: const Icon(Icons.delete_sweep_outlined, size: 16),
      label: const Text('清空', style: TextStyle(fontSize: 12)),
    );
  }

  String _buildPetPreview(Map<String, dynamic> chat) {
    final messages = chat['messages'] as List? ?? [];
    if (messages.isEmpty) return '暂无消息';
    final last = messages.last as Map?;
    final role = last?['role'] == 'user' ? '你' : '雪乃';
    final content = last?['content']?.toString() ?? '';
    return '$role: ${content.length > 20 ? '${content.substring(0, 20)}...' : content}';
  }

  String _formatTimeMs(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}';
  }
}

// ═══════════════════════════════════════════
// _SessionPanel — 折叠面板组件
// ═══════════════════════════════════════════

class _SessionPanel extends StatefulWidget {
  final String title;
  final int count;
  final List<_SessionItem> sessions;
  final VoidCallback onNew;
  final void Function(String id) onTap;
  final void Function(String id) onDelete;
  final Widget? Function(String id)? trailingBuilder;

  const _SessionPanel({
    required this.title,
    required this.count,
    required this.sessions,
    required this.onNew,
    required this.onTap,
    required this.onDelete,
    this.trailingBuilder,
  });

  @override
  State<_SessionPanel> createState() => _SessionPanelState();
}

class _SessionPanelState extends State<_SessionPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 折叠头
          InkWell(
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(12),
              bottom: _expanded ? Radius.zero : const Radius.circular(12),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer),
                    ),
                  ),
                  const Spacer(),
                  // 新建按钮
                  _MiniBtn(
                    icon: Icons.add,
                    tooltip: '新建${widget.title}',
                    onTap: () {
                      widget.onNew();
                      setState(() => _expanded = true);
                    },
                  ),
                  // 自定义尾部按钮（如清空）
                  if (widget.trailingBuilder != null)
                    widget.trailingBuilder!(widget.sessions.firstOrNull?.id ?? '') ?? const SizedBox.shrink(),
                  // 展开/收起
                  _MiniBtn(
                    icon: _expanded ? Icons.expand_less : Icons.expand_more,
                    tooltip: _expanded ? '收起' : '展开',
                    onTap: () => setState(() => _expanded = !_expanded),
                  ),
                ],
              ),
            ),
          ),
          // 展开列表
          if (_expanded)
            ...(widget.sessions.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          '暂无${widget.title}记录',
                          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                        ),
                      ),
                    ),
                  ]
                : widget.sessions.map((session) => Dismissible(
              key: Key(session.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Icon(Icons.delete, color: cs.onErrorContainer),
              ),
              confirmDismiss: (_) async {
                return await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除对话'),
                    content: Text('确定要删除这条${widget.title}记录吗？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
                    ],
                  ),
                ) ?? false;
              },
              onDismissed: (_) => widget.onDelete(session.id),
              child: _SessionTile(
                item: session,
                onTap: () => widget.onTap(session.id),
              ),
            ))),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
// 内部数据/组件
// ═══════════════════════════════════════════

class _SessionItem {
  final String id;
  final String title;
  final String subtitle;
  final String? updatedAt;
  final bool isActive;
  const _SessionItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.updatedAt,
    this.isActive = false,
  });
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _MiniBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final _SessionItem item;
  final VoidCallback onTap;
  const _SessionTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: item.isActive ? cs.primaryContainer : cs.surfaceContainerHighest,
              radius: 16,
              child: Icon(
                Icons.chat_bubble_outline,
                size: 16,
                color: item.isActive ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontWeight: item.isActive ? FontWeight.bold : FontWeight.normal,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.subtitle.isNotEmpty)
                    Text(
                      item.subtitle,
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (item.updatedAt != null)
              Text(
                item.updatedAt!,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
          ],
        ),
      ),
    );
  }
}
