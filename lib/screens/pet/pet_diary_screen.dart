// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';

class PetDiaryScreen extends StatefulWidget {
  const PetDiaryScreen({super.key});

  @override
  State<PetDiaryScreen> createState() => _PetDiaryScreenState();
}

class _PetDiaryScreenState extends State<PetDiaryScreen> {
  final List<Map<String, dynamic>> _entries = [];

  Future<void> _addEntry() async {
    final contentController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('写日记'),
        content: TextField(
          controller: contentController,
          maxLines: 4,
          decoration:
              const InputDecoration(hintText: '今天糯糯发生了什么...'),
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
      setState(() {
        _entries.insert(0, {
          'id': DateTime.now().microsecondsSinceEpoch.toString(),
          'content': result.trim(),
          'date': DateTime.now().toIso8601String(),
          'mood': '📝',
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        child: const Icon(Icons.add),
      ),
      body: _entries.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('📖', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 12),
                  Text('还没有日记条目~',
                      style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('点击 + 添加第一条日记',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _entries.length,
              itemBuilder: (context, i) {
                final entry = _entries[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Text(entry['mood'] as String? ?? '📝',
                        style: const TextStyle(fontSize: 24)),
                    title: Text(entry['content'] as String? ?? '',
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    subtitle: Text(entry['date'] as String? ?? '',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                  ),
                );
              },
            ),
    );
  }
}
