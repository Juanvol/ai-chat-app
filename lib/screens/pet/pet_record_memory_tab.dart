// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../../services/pet/knowledge/models/memory_entry.dart';
import '../../services/pet/knowledge/models/user_profile.dart';
import '../../services/pet/knowledge/memory/memory_store.dart';
import '../../services/pet/pet_overlay_host.dart';

/// 记忆 Tab — 独立管理搜索/筛选/加载状态
class PetRecordMemoryTab extends StatefulWidget {
  final MemoryStore? memoryStore;

  const PetRecordMemoryTab({super.key, required this.memoryStore});

  @override
  State<PetRecordMemoryTab> createState() => PetRecordMemoryTabState();
}

class PetRecordMemoryTabState extends State<PetRecordMemoryTab> {
  List<MemoryEntry> _memories = [];
  bool _loading = true;
  String? _error;
  MemoryTag? _filterTag;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  UserProfile? _profile;
  bool _organizing = false;
  String? _organizeResult;
  List<MemoryEntry>? _orgUpdated;
  List<String>? _orgDeleted;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final ms = widget.memoryStore;
    if (ms == null) { if (mounted) setState(() => _loading = false); return; }
    setState(() { _loading = true; _error = null; });
    try {
      _memories = await ms.loadAll(tag: _filterTag);
      if (_searchQuery.isNotEmpty) {
        _memories = _memories.where((m) => m.content.contains(_searchQuery)).toList();
      }
      try { _profile = await ms.buildProfileAsync(); } catch (_) {}
    } catch (e) { _error = '加载失败，下拉重试'; _memories = []; }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _organizeMemories() async {
    final ms = widget.memoryStore;
    if (ms == null) return;
    setState(() => _organizing = true);
    try {
      final result = await ms.organizeIfNeeded(force: true);
      if (!mounted) return;
      if (result == null) {
        _organizeResult = '还没有记忆可以整理';
      } else {
        _orgUpdated = result.updated;
        _orgDeleted = result.deleted;
        _organizeResult = result.updated.isNotEmpty || result.deleted.isNotEmpty ? 'ok' : 'noop';
      }
      await load();
    } catch (e) {
      _organizeResult = '整理失败';
    }
    if (mounted) setState(() => _organizing = false);
  }

  Future<void> _deleteMemory(MemoryEntry m) async {
    final ms = widget.memoryStore;
    if (ms == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记忆'),
        content: Text('确定删除「${m.content.length > 30 ? '${m.content.substring(0, 30)}...' : m.content}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await ms.deleteMemory(m.id);
      if (mounted) {
        _memories.removeWhere((x) => x.id == m.id);
        setState(() {});
      }
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
          TextButton(onPressed: () => load(), child: const Text('重试')),
        ]),
      );
    }

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_memories.isEmpty && _searchQuery.isEmpty && _profile == null) {
      return _buildEmpty(scheme);
    }

    return CustomScrollView(
      slivers: [
        // 搜索栏
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '搜索记忆...',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                        load();
                      })
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (v) {
                _searchQuery = v.trim();
                load();
              },
            ),
          ),
        ),
        // AI 画像 — 上滑即收起，放大列表空间
        if (_profile != null && _searchQuery.isEmpty && _filterTag == null)
          SliverToBoxAdapter(child: _buildProfileCard(scheme)),
        // 筛选
        SliverToBoxAdapter(child: _buildFilterRow(scheme)),
        // 操作栏
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(children: [
              Text('${_memories.length} 条记忆', style: TextStyle(fontSize: 12, color: scheme.onSurface.withAlpha(150))),
              const Spacer(),
              TextButton.icon(
                onPressed: _organizing ? null : _organizeMemories,
                icon: _organizing
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.psychology, size: 16),
                label: Text(_organizing ? '整理中...' : 'AI 整理', style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
            ]),
          ),
        ),
        // 整理结果
        if (_organizeResult != null) SliverToBoxAdapter(child: _buildOrganizeResult(scheme)),
        // 空搜索结果
        if (_memories.isEmpty && _searchQuery.isNotEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.search_off, size: 40, color: Colors.grey),
                const SizedBox(height: 8),
                Text('没有找到「$_searchQuery」相关的记忆', style: TextStyle(color: scheme.onSurface.withAlpha(120))),
              ]),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _buildMemoryCard(scheme, _memories[i]),
              childCount: _memories.length,
            ),
          ),
        // 底部留白
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  Widget _buildFilterRow(ColorScheme scheme) {
    final tagCounts = <MemoryTag, int>{};
    for (final m in _memories) { tagCounts[m.tag] = (tagCounts[m.tag] ?? 0) + 1; }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        _filterChip(scheme, '全部', null, _memories.length),
        const SizedBox(width: 6),
        ...MemoryTag.values.map((tag) {
          final count = tagCounts[tag] ?? 0;
          if (count == 0 && _filterTag != tag) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _filterChip(scheme, '${_tagIcon(tag)} ${_tagLabel(tag)}', tag, count),
          );
        }),
      ]),
    );
  }

  Widget _filterChip(ColorScheme scheme, String label, MemoryTag? tag, int count) {
    final active = _filterTag == tag;
    return GestureDetector(
      onTap: () { setState(() => _filterTag = tag); load(); },
      child: Chip(
        label: Text('$label ($count)', style: TextStyle(fontSize: 11, color: active ? scheme.onPrimary : scheme.onSurface.withAlpha(180))),
        backgroundColor: active ? scheme.primary : scheme.surfaceContainerHighest,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide.none,
      ),
    );
  }

  Widget _buildOrganizeResult(ColorScheme scheme) {
    if (_organizeResult == 'noop') {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: scheme.primaryContainer.withAlpha(60), borderRadius: BorderRadius.circular(10)),
        child: Text('${petOverlayController.petSelfRef}检查了 ${_memories.length} 条记忆，\n没有需要合并或清理的内容', style: TextStyle(fontSize: 12, color: scheme.onSurface.withAlpha(180))),
      );
    }
    if (_organizeResult == 'ok' && _orgUpdated != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: scheme.primaryContainer.withAlpha(60), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('🔗 合并更新了 ${_orgUpdated!.length} 条记忆', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary)),
          if (_orgUpdated!.isNotEmpty)
            ..._orgUpdated!.take(3).map((m) => Text('· ${m.content}', style: TextStyle(fontSize: 11, color: scheme.onSurface.withAlpha(150)))),
          if (_orgDeleted != null && _orgDeleted!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('🗑️ 清理了 ${_orgDeleted!.length} 条过期记忆', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.error)),
            ..._orgDeleted!.take(3).map((id) => Text('· 已删除: $id', style: TextStyle(fontSize: 11, color: scheme.onSurface.withAlpha(100)))),
          ],
          const SizedBox(height: 6),
          TextButton(onPressed: () => setState(() { _organizeResult = null; _orgUpdated = null; _orgDeleted = null; }), child: const Text('知道了', style: TextStyle(fontSize: 12))),
        ]),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: scheme.errorContainer.withAlpha(60), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        const Icon(Icons.info, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(_organizeResult ?? '', style: TextStyle(fontSize: 12, color: scheme.onSurface.withAlpha(180)))),
        TextButton(onPressed: () => setState(() => _organizeResult = null), child: const Text('关闭', style: TextStyle(fontSize: 12))),
      ]),
    );
  }

  Widget _buildEmpty(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.auto_awesome, size: 56, color: Colors.grey),
          const SizedBox(height: 16),
          Text('${petOverlayController.petSelfRef}眼中的你', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          const SizedBox(height: 12),
          Text(
            '${petOverlayController.petSelfRef}刚开始了解你 ✨\n\n'
            '每一次喂食、玩耍、抚摸，\n${petOverlayController.petSelfRef}都会记住，慢慢拼出关于你的一切。\n\n'
            '去互动页面和${petOverlayController.petSelfRef}玩一会儿吧～',
            style: TextStyle(fontSize: 13, height: 1.7, color: scheme.onSurface.withAlpha(150)),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }

  Widget _buildProfileCard(ColorScheme scheme) {
    final p = _profile!;
    if (p.interests.isEmpty && p.habitWeights.isEmpty && p.recentTopics.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [scheme.primaryContainer.withAlpha(80), scheme.surfaceContainerHighest]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primaryContainer.withAlpha(120)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.psychology, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
          Text('${petOverlayController.petSelfRef}眼中的你', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        ]),
        const SizedBox(height: 10),
        if (p.interests.isNotEmpty) ...[
          Text('🎯 兴趣', style: TextStyle(fontSize: 11, color: scheme.onSurface.withAlpha(120))),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 2, children: p.interests.take(6).map((t) => Chip(label: Text(t, style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)).toList()),
          const SizedBox(height: 8),
        ],
        if (p.habitWeights.isNotEmpty) ...[
          Text('🔄 习惯', style: TextStyle(fontSize: 11, color: scheme.onSurface.withAlpha(120))),
          const SizedBox(height: 4),
          ...p.habitWeights.entries.take(4).map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              Expanded(child: Text(e.key, style: const TextStyle(fontSize: 11))),
              const SizedBox(width: 8),
              ClipRRect(borderRadius: BorderRadius.circular(3), child: SizedBox(width: 80, height: 6, child: LinearProgressIndicator(value: e.value, backgroundColor: scheme.surfaceContainerHighest))),
            ]),
          )),
          const SizedBox(height: 8),
        ],
        if (p.recentTopics.isNotEmpty) ...[
          Text('💬 最近话题', style: TextStyle(fontSize: 11, color: scheme.onSurface.withAlpha(120))),
          const SizedBox(height: 4),
          Text(p.recentTopics.take(4).join(' · '), style: TextStyle(fontSize: 11, color: scheme.onSurface.withAlpha(180))),
        ],
      ]),
    );
  }

  Widget _buildMemoryCard(ColorScheme scheme, MemoryEntry memory) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(_tagIcon(memory.tag), style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              Text(_tagLabel(memory.tag), style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(_formatDate(memory.createdAt), style: TextStyle(fontSize: 10, color: scheme.onSurface.withAlpha(100))),
            ]),
            const SizedBox(height: 6),
            Text(memory.content, style: TextStyle(fontSize: 13, height: 1.5, color: scheme.onSurface)),
            const SizedBox(height: 4),
            Text(memory.source.name, style: TextStyle(fontSize: 10, color: scheme.onSurface.withAlpha(100))),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('重要性: ${memory.importance.toStringAsFixed(1)}', style: TextStyle(fontSize: 10, color: scheme.onSurface.withAlpha(100))),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.delete_outline, size: 16), onPressed: () => _deleteMemory(memory), visualDensity: VisualDensity.compact),
            ]),
          ]),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _tagIcon(MemoryTag tag) => switch (tag) {
    MemoryTag.fact => '📋', MemoryTag.habit => '🔄', MemoryTag.interest => '💚',
    MemoryTag.event => '📌', MemoryTag.reminder => '⏰',
  };

  String _tagLabel(MemoryTag tag) => switch (tag) {
    MemoryTag.fact => '事实', MemoryTag.habit => '习惯', MemoryTag.interest => '兴趣',
    MemoryTag.event => '事件', MemoryTag.reminder => '提醒',
  };
}
