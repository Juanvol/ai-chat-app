// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../../services/pet/knowledge/models/memory_entry.dart';
import '../../services/pet/pet_overlay_host.dart';
import 'pet_record_memory_tab.dart';
import 'pet_record_diary_tab.dart';

/// 记忆与日记 — 顶栏切换两个 Tab
class PetRecordScreen extends StatefulWidget {
  const PetRecordScreen({super.key});
  @override
  State<PetRecordScreen> createState() => _PetRecordScreenState();
}

enum _RecordView { memory, diary }

class _PetRecordScreenState extends State<PetRecordScreen> {
  _RecordView _view = _RecordView.memory;
  final _memoryKey = GlobalKey<PetRecordMemoryTabState>();
  bool _initTriggered = false;

  @override
  void initState() {
    super.initState();
    petOverlayController.kbReady.addListener(_onKbReady);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureKB());
  }

  @override
  void dispose() {
    petOverlayController.kbReady.removeListener(_onKbReady);
    super.dispose();
  }

  void _onKbReady() {
    if (mounted) setState(() {});
  }

  void _ensureKB() {
    if (_initTriggered) return;
    _initTriggered = true;
    petOverlayController.ensureKB();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kb = petOverlayController.knowledgeBase;
    final ready = petOverlayController.kbReady.value && kb != null;

    return Scaffold(
      appBar: AppBar(title: const Text('记忆与日记'), centerTitle: true),
      body: !ready
          ? Center(
              child: Text('${petOverlayController.petSelfRef}正在准备记忆系统...',
                  style: TextStyle(color: scheme.onSurface.withAlpha(180), fontSize: 14)),
            )
          : Column(
              children: [
                _buildTopBar(scheme),
                Expanded(
                  child: IndexedStack(
                    index: _view.index,
                    children: [
                      PetRecordMemoryTab(key: _memoryKey, memoryStore: kb!.memoryStore),
                      PetRecordDiaryTab(knowledgeBase: kb!),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: _view == _RecordView.memory
          ? FloatingActionButton.small(
              onPressed: () => _addMemory(context),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildTopBar(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: SegmentedButton<_RecordView>(
        segments: const [
          ButtonSegment(value: _RecordView.memory, label: Text('🧠 记忆'), icon: Icon(Icons.psychology, size: 16)),
          ButtonSegment(value: _RecordView.diary, label: Text('📖 日记'), icon: Icon(Icons.book_outlined, size: 16)),
        ],
        selected: {_view},
        onSelectionChanged: (s) => setState(() => _view = s.first),
      ),
    );
  }

  Future<void> _addMemory(BuildContext context) async {
    final ms = petOverlayController.knowledgeBase?.memoryStore;
    if (ms == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先开启宠物')));
      }
      return;
    }
    final ctrl = TextEditingController();
    MemoryTag tag = MemoryTag.fact;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        title: Text('告诉${petOverlayController.petSelfRef}一件事'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: '想让${petOverlayController.petSelfRef}记住什么？',
                hintText: '比如：主人每天早上都要喝一杯咖啡 ☕',
              ),
              maxLines: 2,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MemoryTag>(
              initialValue: tag,
              items: MemoryTag.values.map((t) => DropdownMenuItem(
                value: t,
                child: Text('${_tagIcon(t)} ${_tagLabel(t)}', style: const TextStyle(fontSize: 14)),
              )).toList(),
              onChanged: (v) { if (v != null) setDialogState(() => tag = v); },
              decoration: const InputDecoration(labelText: '这是什么类型的？'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, {'content': ctrl.text, 'tag': tag}), child: const Text('保存')),
        ],
      )),
    );

    if (result == null || !mounted) return;
    final content = (result['content'] as String?)?.trim() ?? '';
    if (content.isEmpty) return;

    try {
      await ms.addMemory(content, result['tag'] as MemoryTag);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${petOverlayController.petSelfRef}记住啦~ 🐾'), duration: const Duration(seconds: 1)),
        );
        _memoryKey.currentState?.load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存失败')));
      }
    }
  }

  String _tagIcon(MemoryTag tag) => switch (tag) {
    MemoryTag.fact => '📋', MemoryTag.habit => '🔄', MemoryTag.interest => '💚',
    MemoryTag.event => '📌', MemoryTag.reminder => '⏰',
  };

  String _tagLabel(MemoryTag tag) => switch (tag) {
    MemoryTag.fact => '事实', MemoryTag.habit => '习惯', MemoryTag.interest => '兴趣',
    MemoryTag.event => '事件', MemoryTag.reminder => '提醒',
  };
}
