// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/pet/pet_diary_service.dart';

class PetDiaryScreen extends StatefulWidget {
  const PetDiaryScreen({super.key});

  @override
  State<PetDiaryScreen> createState() => _PetDiaryScreenState();
}

class _PetDiaryScreenState extends State<PetDiaryScreen> {
  @override
  void initState() {
    super.initState();
    // 确保 diary service 已初始化
    Future.microtask(() {
      if (!mounted) return;
      context.read<PetDiaryService>().init();
    });
  }

  Future<void> _addEntry(PetDiaryService svc) async {
    final contentController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('写日记'),
        content: TextField(
          controller: contentController,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '今天糯糯发生了什么...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, contentController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await svc.addEntry(content: result.trim());
    }
  }

  Future<void> _confirmClear(PetDiaryService svc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日记'),
        content: const Text('确定要删除所有日记条目吗？此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定清空'),
          ),
        ],
      ),
    );
    if (ok == true) await svc.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📖 糯糯日记'),
        actions: [
          Consumer<PetDiaryService>(
            builder: (_, svc, __) => svc.entries.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: '清空日记',
                    onPressed: () => _confirmClear(svc),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final svc = context.read<PetDiaryService>();
          _addEntry(svc);
        },
        child: const Icon(Icons.add),
      ),
      body: Consumer<PetDiaryService>(
        builder: (context, svc, _) {
          if (svc.entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('📖', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text('还没有日记条目~',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          )),
                  const SizedBox(height: 8),
                  Text(
                    '糯糯的事件会自动记录在这里\n也可以点击 + 手动添加',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: svc.entries.length,
            itemBuilder: (context, i) {
              final entry = svc.entries[i];
              final dateStr = entry['date'] as String? ?? '';
              final date = DateTime.tryParse(dateStr);
              final dateLabel = date != null
                  ? '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
                  : dateStr;
              final isAuto = entry['type'] != 'manual';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading:
                      Text(entry['mood'] as String? ?? '📝', style: const TextStyle(fontSize: 24)),
                  title: Text(entry['content'] as String? ?? '',
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: Row(
                    children: [
                      if (isAuto)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('自动',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer)),
                        ),
                      Text(dateLabel,
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => svc.deleteEntry(entry['id'] as String? ?? ''),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
