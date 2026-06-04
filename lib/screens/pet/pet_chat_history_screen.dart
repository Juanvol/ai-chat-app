// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/pet/pet_chat_service.dart';

const _agentBridge = MethodChannel('com.example.deepseek_chat/pet_agent_bridge');

/// 聊天记录管理 — 宠物聊天（Hive）+ 弹窗聊天（原生 SharedPreferences）
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
  List<Map<String, dynamic>> _petChats = [];
  List<Map<String, dynamic>> _popupMsgs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final petChats = await widget.chatService.listChats();
    final popupMsgs = await _fetchPopupHistory();
    if (!mounted) return;
    setState(() {
      _petChats = petChats;
      _popupMsgs = popupMsgs;
      _loading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _fetchPopupHistory() async {
    try {
      final raw = await _agentBridge.invokeMethod('getPopupHistory');
      if (raw is List) {
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
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

  Future<void> _clearPopupHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除弹窗聊天记录'),
        content: const Text('确定要清除所有弹窗聊天记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清除')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _agentBridge.invokeMethod('clearPopupHistory');
    } catch (_) {}
    _loadAll();
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
          : _petChats.isEmpty && _popupMsgs.isEmpty
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
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // ── 弹窗聊天 ──
                    if (_popupMsgs.isNotEmpty) ...[
                      _SectionHeader(
                        title: '弹窗聊天',
                        trailing: TextButton.icon(
                          onPressed: _clearPopupHistory,
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('清除', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.chat, size: 16, color: cs.primary),
                                const SizedBox(width: 8),
                                Text('最近弹窗对话', style: TextStyle(fontWeight: FontWeight.w500, color: cs.onSurface)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_popupMsgs.length} 条消息',
                              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                            ),
                            if (_popupMsgs.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                _popupMsgs.last['text']?.toString() ?? '',
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // ── 宠物聊天 ──
                    if (_petChats.isNotEmpty) ...[
                      _SectionHeader(title: '宠物聊天'),
                      ..._petChats.map((chat) => Dismissible(
                        key: Key(chat['id'] as String? ?? ''),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: cs.errorContainer,
                          child: Icon(Icons.delete, color: cs.onErrorContainer),
                        ),
                        confirmDismiss: (_) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('删除对话'),
                              content: const Text('确定要删除这条宠物聊天记录吗？'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
                              ],
                            ),
                          ) ?? false;
                        },
                        onDismissed: (_) => _deletePetChat(chat['id'] as String),
                        child: _PetChatTile(
                          chat: chat,
                          isActive: chat['id'] == widget.currentChatId,
                          onTap: () => Navigator.pop(context, chat['id']),
                        ),
                      )),
                    ],
                  ],
                ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
      child: Row(
        children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _PetChatTile extends StatelessWidget {
  final Map<String, dynamic> chat;
  final bool isActive;
  final VoidCallback onTap;
  const _PetChatTile({required this.chat, required this.isActive, required this.onTap});

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = chat['title'] as String? ?? '新对话';
    final updatedAt = chat['updatedAt'] as String?;
    final messages = chat['messages'] as List? ?? [];
    final preview = messages.isNotEmpty
        ? '${messages.last['role'] == 'user' ? '你' : '雪乃'}: ${messages.last['content'] ?? ''}'
        : '暂无消息';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isActive ? cs.primaryContainer : cs.surfaceContainerHighest,
        radius: 18,
        child: Icon(Icons.pets, size: 18, color: isActive ? cs.primary : cs.onSurfaceVariant),
      ),
      title: Text(title, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(preview, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(_formatTime(updatedAt), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
      onTap: onTap,
    );
  }
}
