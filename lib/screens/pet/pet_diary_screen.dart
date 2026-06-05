// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../../services/pet/knowledge/knowledge_base.dart';
import '../../services/pet/knowledge/models/diary_entry.dart';
import '../../config/theme.dart';

class PetDiaryScreen extends StatefulWidget {
  final KnowledgeBase? knowledgeBase;

  const PetDiaryScreen({super.key, this.knowledgeBase});

  @override
  State<PetDiaryScreen> createState() => _PetDiaryScreenState();
}

class _PetDiaryScreenState extends State<PetDiaryScreen> {
  List<DiaryEntry> _entries = [];
  bool _loading = true;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final kb = widget.knowledgeBase;
    if (kb == null) return;

    setState(() => _loading = true);

    if (_selectedDate != null) {
      _entries = await kb.diaryStore.loadByDate(_selectedDate!);
    } else {
      _entries = await kb.getRecentDiary(days: 30);
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addManualEntry() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('写日记'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '今天糯糯发生了什么...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (text != null && text.trim().isNotEmpty) {
      await widget.knowledgeBase!.diaryStore
          .recordEvent('manual', detail: text.trim());
      _loadEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.knowledgeBase == null) {
      return const Center(child: Text('知识库未初始化'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('📖 糯糯日记')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addManualEntry,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _buildDatePicker(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? _buildEmpty()
                    : _buildEntryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate ?? DateTime.now(),
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                _selectedDate = picked;
                _loadEntries();
              }
            },
          ),
          if (_selectedDate != null)
            Chip(
              label: Text(
                  '${_selectedDate!.year}-${_selectedDate!.month}-${_selectedDate!.day}'),
              onDeleted: () {
                _selectedDate = null;
                _loadEntries();
              },
            )
          else
            const Chip(label: Text('最近30天')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Text(
        _selectedDate != null
            ? '这天还没有日记'
            : '还没有日记~ 和糯糯互动就会自动记日记喵~',
        style: TextStyle(color: C.scheme.onSurface.withAlpha(128)),
      ),
    );
  }

  Widget _buildEntryList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _entries.length,
      itemBuilder: (context, index) => _buildEntryCard(_entries[index]),
    );
  }

  Widget _buildEntryCard(DiaryEntry entry) {
    final isHighlight = entry.type == DiaryEntryType.highlight;
    final isSummary = entry.type == DiaryEntryType.summary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isHighlight
          ? C.scheme.primaryContainer.withAlpha(80)
          : isSummary
              ? C.scheme.secondaryContainer.withAlpha(80)
              : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.mood, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.content,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSummary ? FontWeight.bold : FontWeight.normal,
                      color: C.scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.date.hour.toString().padLeft(2, '0')}:${entry.date.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: C.scheme.onSurface.withAlpha(128),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
