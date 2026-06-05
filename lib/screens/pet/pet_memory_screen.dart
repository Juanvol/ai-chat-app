// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../../services/pet/knowledge/memory/memory_store.dart';
import '../../services/pet/knowledge/models/memory_entry.dart';
import '../../config/theme.dart';

class PetMemoryScreen extends StatefulWidget {
  final MemoryStore? memoryStore;

  const PetMemoryScreen({super.key, this.memoryStore});

  @override
  State<PetMemoryScreen> createState() => _PetMemoryScreenState();
}

class _PetMemoryScreenState extends State<PetMemoryScreen> {
  List<MemoryEntry> _memories = [];
  MemoryTag? _filterTag;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    final ms = widget.memoryStore;
    if (ms == null) return;

    setState(() => _loading = true);
    _memories = await ms.loadAll(tag: _filterTag);
    if (mounted) setState(() => _loading = false);
  }

  Widget _buildTagFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('全部'),
            selected: _filterTag == null,
            onSelected: (_) { _filterTag = null; _loadMemories(); },
          ),
          const SizedBox(width: 8),
          ...MemoryTag.values.map((tag) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(_tagLabel(tag)),
              selected: _filterTag == tag,
              onSelected: (selected) {
                _filterTag = selected ? tag : null;
                _loadMemories();
              },
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Text(
        '还没有记忆~ 多和糯糯互动，糯糯会慢慢了解主人喵~',
        style: TextStyle(color: C.scheme.onSurface.withAlpha(128)),
      ),
    );
  }

  Widget _buildMemoryList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _memories.length,
      itemBuilder: (context, index) => _buildMemoryCard(_memories[index]),
    );
  }

  Widget _buildMemoryCard(MemoryEntry memory) {
    final importanceColor = memory.importance > 0.7
        ? Colors.amber
        : memory.importance > 0.4
            ? Colors.grey
            : Colors.grey.withAlpha(100);

    return Dismissible(
      key: Key(memory.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: C.scheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除记忆'),
            content: Text('确定删除「${memory.content}」？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
            ],
          ),
        );
      },
      onDismissed: (_) {
        widget.memoryStore?.deleteMemory(memory.id);
        _loadMemories();
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () => _editMemory(memory),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  memory.importance > 0.7 ? Icons.star : Icons.star_border,
                  color: importanceColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _tagColor(memory.tag).withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _tagLabel(memory.tag),
                    style: TextStyle(fontSize: 11, color: _tagColor(memory.tag)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(memory.content, style: const TextStyle(fontSize: 14)),
                      if (memory.source == MemorySource.llm)
                        Text('AI整理', style: TextStyle(fontSize: 10, color: C.scheme.onSurface.withAlpha(100))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editMemory(MemoryEntry memory) async {
    final contentCtrl = TextEditingController(text: memory.content);
    final importanceCtrl = TextEditingController(text: memory.importance.toStringAsFixed(1));
    MemoryTag selectedTag = memory.tag;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑记忆'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(labelText: '内容'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MemoryTag>(
                initialValue: selectedTag,
                items: MemoryTag.values.map((t) => DropdownMenuItem(
                  value: t,
                  child: Text(_tagLabel(t)),
                )).toList(),
                onChanged: (v) { if (v != null) selectedTag = v; },
                decoration: const InputDecoration(labelText: '分类'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: importanceCtrl,
                decoration: const InputDecoration(labelText: '重要性 (0.0-1.0)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, {
            'content': contentCtrl.text,
            'tag': selectedTag,
            'importance': double.tryParse(importanceCtrl.text) ?? memory.importance,
          }), child: const Text('保存')),
        ],
      ),
    );

    if (result != null && mounted) {
      await widget.memoryStore?.updateMemory(
        memory.id,
        content: result['content'] as String,
        tag: result['tag'] as MemoryTag,
        importance: result['importance'] as double,
      );
      _loadMemories();
    }
  }

  Future<void> _addMemory() async {
    final contentCtrl = TextEditingController();
    MemoryTag selectedTag = MemoryTag.fact;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加记忆'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: contentCtrl,
              decoration: const InputDecoration(labelText: '内容', hintText: '主人喜欢喝咖啡'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MemoryTag>(
              initialValue: selectedTag,
              items: MemoryTag.values.map((t) => DropdownMenuItem(
                value: t,
                child: Text(_tagLabel(t)),
              )).toList(),
              onChanged: (v) { if (v != null) selectedTag = v; },
              decoration: const InputDecoration(labelText: '分类'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, {
              'content': contentCtrl.text,
              'tag': selectedTag,
            }),
            child: const Text('添加'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      await widget.memoryStore?.addMemory(
        result['content'] as String,
        result['tag'] as MemoryTag,
      );
      _loadMemories();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildTagFilter(),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMemory,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_memories.isEmpty) return _buildEmpty();
    return _buildMemoryList();
  }

  String _tagLabel(MemoryTag tag) => switch (tag) {
    MemoryTag.fact => '事实',
    MemoryTag.habit => '习惯',
    MemoryTag.interest => '兴趣',
    MemoryTag.event => '事件',
    MemoryTag.reminder => '提醒',
  };

  Color _tagColor(MemoryTag tag) => switch (tag) {
    MemoryTag.fact => Colors.blue,
    MemoryTag.habit => Colors.orange,
    MemoryTag.interest => Colors.green,
    MemoryTag.event => Colors.purple,
    MemoryTag.reminder => Colors.red,
  };
}
