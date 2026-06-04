// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../services/pet/pet_chat_service.dart';
import '../../services/pet/pet_logger.dart';
import '../../widgets/shimmer_box.dart';

class PetMemoryScreen extends StatefulWidget {
  const PetMemoryScreen({super.key});

  @override
  State<PetMemoryScreen> createState() => _PetMemoryScreenState();
}

class _PetMemoryScreenState extends State<PetMemoryScreen> {
  final PetChatService _chatSvc = PetChatService();
  List<Map<String, dynamic>> _memories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _memories = await _chatSvc.listMemories();
    } catch (e) {
      PetLogger().error('PetMemoryScreen', '_load failed', e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _importFromConversations() async {
    try {
      final convBox = await Hive.openBox('conversations');
      final convs = convBox.values.cast<Map>().toList();
      if (convs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有可导入的对话')),
          );
        }
        return;
      }

      // 从对话中提取摘要，每条对话取最后一条 AI 回复作为记忆
      final summaries = <Map<String, dynamic>>[];
      for (final c in convs) {
        final msgs = c['messages'] as List<dynamic>? ?? [];
        final title = c['title'] as String? ?? '未知对话';
        // 取最后一条 assistant 消息
        String? lastAi;
        for (final m in msgs.reversed) {
          if (m is Map && m['role'] == 'assistant') {
            lastAi = m['content'] as String?;
            break;
          }
        }
        if (lastAi != null && lastAi.isNotEmpty) {
          final short = lastAi.length > 100 ? '${lastAi.substring(0, 100)}...' : lastAi;
          summaries.add({'id': c['id'] ?? '', 'title': title, 'summary': short});
        }
      }

      if (summaries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('对话中没有可提取的 AI 回复')),
          );
        }
        return;
      }

      final count = await _chatSvc.importMemories(summaries);
      PetLogger().info('PetMemoryScreen', 'imported $count memories');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 $count 条记忆')),
        );
      }
      await _load();
    } catch (e) {
      PetLogger().error('PetMemoryScreen', '_import failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入失败，请重试')),
        );
      }
    }
  }

  Future<void> _deleteMemory(String id) async {
    await _chatSvc.deleteMemory(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Column(children: List.generate(4, (i) => ShimmerCard(lines: i == 0 ? 3 : 1)));
    }

    if (_memories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🧠', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('还没有记忆，去和糯糯聊天或分享对话吧~',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _importFromConversations,
              icon: const Icon(Icons.file_download),
              label: const Text('导入对话记忆'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text('共 ${_memories.length} 条记忆',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.7),
                      fontSize: 13)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _importFromConversations,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('导入更多'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _memories.length,
            itemBuilder: (context, i) {
              final m = _memories[i];
              final content = m['content'] as String? ?? '';
              final sourceTitle = m['sourceTitle'] as String?;
              final importedAt = m['importedAt'] as String? ?? '';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      sourceTitle != null ? '来自：$sourceTitle' : importedAt,
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.6)),
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _deleteMemory(m['id'] as String? ?? ''),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
