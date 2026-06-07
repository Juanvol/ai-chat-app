// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../../services/pet/knowledge/knowledge_base.dart';
import '../../services/pet/knowledge/models/diary_entry.dart';
import '../../services/pet/pet_overlay_host.dart';

/// 日记 Tab — 时间线 + 日期选择
class PetRecordDiaryTab extends StatefulWidget {
  final KnowledgeBase knowledgeBase;

  const PetRecordDiaryTab({super.key, required this.knowledgeBase});

  @override
  State<PetRecordDiaryTab> createState() => _PetRecordDiaryTabState();
}

class _PetRecordDiaryTabState extends State<PetRecordDiaryTab> {
  List<DiaryEntry> _entries = [];
  bool _loading = true;
  String? _error;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final kb = widget.knowledgeBase;
      if (_selectedDate != null) {
        final all = await kb.getRecentDiary(days: 7);
        _entries = all.where((e) =>
          e.date.year == _selectedDate!.year &&
          e.date.month == _selectedDate!.month &&
          e.date.day == _selectedDate!.day
        ).toList();
      } else {
        _entries = await kb.getRecentDiary(days: 7);
      }
    } catch (e) {
      _error = '加载失败，下拉重试';
      _entries = [];
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: TextStyle(color: scheme.onSurface.withAlpha(150))),
          const SizedBox(height: 8),
          TextButton(onPressed: load, child: const Text('重试')),
        ]),
      );
    }

    if (_loading) return const Center(child: CircularProgressIndicator());

    // 按日期分组
    final grouped = <String, List<DiaryEntry>>{};
    for (final e in _entries) {
      final key = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}-${e.date.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(e);
    }

    if (grouped.isEmpty) {
      return Column(
        children: [
          _buildDateBar(scheme),
          Expanded(child: _buildEmpty(scheme)),
        ],
      );
    }

    return Column(
      children: [
        _buildDateBar(scheme),
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 80),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: grouped.entries.length,
              itemBuilder: (_, i) {
                final entry = grouped.entries.elementAt(i);
                return _buildDaySection(scheme, entry.key, entry.value);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.book_outlined, size: 56, color: Colors.grey),
          const SizedBox(height: 16),
          Text('${petOverlayController.petSelfRef}的日记本', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface)),
          const SizedBox(height: 12),
          Text(
            _selectedDate != null ? '这一天还没有互动记录' : '每次你和${petOverlayController.petSelfRef}互动，\n这里就会自动生成一条记录',
            style: TextStyle(fontSize: 13, height: 1.7, color: scheme.onSurface.withAlpha(150)),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }

  Widget _buildDateBar(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          onPressed: _selectedDate != null ? () {
            setState(() => _selectedDate = _selectedDate!.subtract(const Duration(days: 1)));
            load();
          } : null,
        ),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate ?? DateTime.now(),
              firstDate: DateTime(2024),
              lastDate: DateTime.now(),
            );
            if (picked != null && mounted) { setState(() => _selectedDate = picked); load(); }
          },
          child: Text(
            _selectedDate != null
                ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
                : '全部日期',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.primary),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          onPressed: _selectedDate != null ? () {
            final next = _selectedDate!.add(const Duration(days: 1));
            if (next.isBefore(DateTime.now()) || next.day == DateTime.now().day) {
              setState(() => _selectedDate = next);
              load();
            }
          } : null,
        ),
        const Spacer(),
        if (_selectedDate != null)
          TextButton(
            onPressed: () { setState(() => _selectedDate = null); load(); },
            child: const Text('全部', style: TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _buildDaySection(ColorScheme scheme, String dateKey, List<DiaryEntry> entries) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(dateKey, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary)),
      ),
      ...entries.map((e) => _buildTimelineItem(scheme, e)),
      const Divider(height: 20),
    ]);
  }

  Widget _buildTimelineItem(ColorScheme scheme, DiaryEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 44,
          child: Text(
            '${entry.date.hour.toString().padLeft(2, '0')}:${entry.date.minute.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 10, color: scheme.onSurface.withAlpha(100)),
          ),
        ),
        Column(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.onSurface.withAlpha(80))),
          Container(width: 1, height: 30, color: scheme.onSurface.withAlpha(30)),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(entry.mood, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text('${petOverlayController.petSelfRef}的瞬间', style: TextStyle(fontSize: 11, color: scheme.onSurface.withAlpha(120))),
              ]),
              const SizedBox(height: 4),
              Text(entry.content, style: TextStyle(fontSize: 13, height: 1.5, color: scheme.onSurface)),
            ]),
          ),
        ),
      ]),
    );
  }
}
