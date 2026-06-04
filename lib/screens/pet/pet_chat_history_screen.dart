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
  String? _activePopupId;
  bool _loading = true;

  // 多选删除
  bool _selectMode = false;
  final _selectedIds = <String>{};

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
      _activePopupId = popupSessions.isNotEmpty ? popupSessions.first.id : null;
      _loading = false;
    });
  }

  Future<void> _deletePetChat(String id) async {
    await widget.chatService.deleteChat(id);
    _loadAll();
  }

  Future<void> _deletePopupSession(String sessionId) async {
    await _popupSvc.deleteSession(sessionId);
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
    if (mounted) {
      setState(() => _activePopupId = session.id);
      await _loadAll();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到「${session.title}」'), duration: const Duration(seconds: 1)),
      );
    }
  }

  // ═══════════════════════════════════════════
  // 多选删除
  // ═══════════════════════════════════════════

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  void _onSelectChanged(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  Future<void> _batchDelete() async {
    final count = _selectedIds.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除选中的 $count 条记录吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );

    if (confirmed != true) return;

    final ids = List<String>.from(_selectedIds);
    for (final id in ids) {
      final isPetChat = _petChats.any((c) => c['id'] == id);
      if (isPetChat) {
        await _deletePetChat(id);
      } else {
        await _deletePopupSession(id);
      }
    }
    _selectedIds.clear();
    setState(() => _selectMode = false);
    await _loadAll();
  }

  Widget _buildSelectBottomBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Text('已选择 ${_selectedIds.length} 项', style: TextStyle(color: cs.onSurface)),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _batchDelete,
              icon: const Icon(Icons.delete_outline),
              label: Text('删除 (${_selectedIds.length})'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天记录'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
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
          ),
          if (_selectMode && _selectedIds.isNotEmpty) _buildSelectBottomBar(),
        ],
      ),
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
          onTap: (id) => Navigator.pop(context, id),
          onDelete: _deletePetChat,
          selectMode: _selectMode,
          selectedIds: _selectedIds,
          onSelectChanged: _onSelectChanged,
          onToggleSelectMode: _toggleSelectMode,
          showSelectButton: true,
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
              isActive: _popupSessions.isNotEmpty && s.id == _activePopupId,
            )).toList(),
            onNew: _newPopupSession,
            onTap: (id) {
              final s = _popupSessions.firstWhere((s) => s.id == id, orElse: () => _popupSessions.first);
              _onPopupSessionTap(s);
            },
            onDelete: _deletePopupSession,
            selectMode: _selectMode,
            selectedIds: _selectedIds,
            onSelectChanged: _onSelectChanged,
            onToggleSelectMode: _toggleSelectMode,
            showSelectButton: false,
          ),
      ],
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
  // 多选
  final bool selectMode;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onSelectChanged;
  final VoidCallback onToggleSelectMode;
  final bool showSelectButton;

  const _SessionPanel({
    required this.title,
    required this.count,
    required this.sessions,
    required this.onNew,
    required this.onTap,
    required this.onDelete,
    this.selectMode = false,
    this.selectedIds = const <String>{},
    required this.onSelectChanged,
    required this.onToggleSelectMode,
    this.showSelectButton = true,
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
                  // 多选按钮（仅一个面板需要显示）
                  if (widget.showSelectButton)
                    _MiniBtn(
                      icon: widget.selectMode ? Icons.close : Icons.checklist,
                      tooltip: widget.selectMode ? '取消选择' : '多选',
                      onTap: widget.onToggleSelectMode,
                    ),
                  // 新建按钮
                  _MiniBtn(
                    icon: Icons.add,
                    tooltip: '新建${widget.title}',
                    onTap: () {
                      widget.onNew();
                      setState(() => _expanded = true);
                    },
                  ),
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
              direction: widget.selectMode ? DismissDirection.none : DismissDirection.endToStart,
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
                onDelete: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('删除对话'),
                      content: Text('确定要删除这条${widget.title}记录吗？'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    widget.onDelete(session.id);
                  }
                },
                selectMode: widget.selectMode,
                isSelected: widget.selectedIds.contains(session.id),
                onSelect: () => widget.onSelectChanged(
                  session.id, !widget.selectedIds.contains(session.id),
                ),
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
  final VoidCallback? onDelete;
  // 多选
  final bool selectMode;
  final bool isSelected;
  final VoidCallback? onSelect;

  const _SessionTile({
    required this.item,
    required this.onTap,
    this.onDelete,
    this.selectMode = false,
    this.isSelected = false,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: selectMode ? onSelect : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // 选择模式下的复选框
            if (selectMode)
              Checkbox(
                value: isSelected,
                onChanged: (_) => onSelect?.call(),
                visualDensity: VisualDensity.compact,
              ),
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
            // 删除按钮（选择模式下隐藏）
            if (onDelete != null && !selectMode) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 18, color: cs.error.withValues(alpha: 0.7)),
                tooltip: '删除',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
