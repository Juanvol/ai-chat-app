// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../../services/pet/suggestion/models/suggestion.dart';
import '../../services/pet/suggestion/suggestion_store.dart';
import '../../services/pet/pet_overlay_host.dart';
import '../../config/theme.dart';

/// ${petOverlayController.petSelfRef}的主动建议历史页。
///
/// 展示${petOverlayController.petSelfRef}自动生成的所有建议——包括轻提醒、场景感知、
/// 深度建议和紧急提醒，按日期分组浏览。
class PetSuggestionScreen extends StatefulWidget {
  const PetSuggestionScreen({super.key});

  @override
  State<PetSuggestionScreen> createState() => _PetSuggestionScreenState();
}

class _PetSuggestionScreenState extends State<PetSuggestionScreen> {
  SuggestionStore? get _store => petOverlayController.suggestionStore;

  Map<String, List<Suggestion>>? _grouped;
  bool _loading = true;
  bool _showHelp = false;

  @override
  void initState() {
    super.initState();
    petOverlayController.kbReady.addListener(_onKbReady);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    petOverlayController.kbReady.removeListener(_onKbReady);
    super.dispose();
  }

  void _onKbReady() {
    if (petOverlayController.kbReady.value) _load();
  }

  Future<void> _load() async {
    if (_store == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final grouped = await _store!.getGrouped(days: 7);
      if (!mounted) return;
      setState(() { _grouped = grouped; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_grouped == null || _grouped!.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        // 帮助按钮
        if (_showHelp) _buildHelpPanel(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: _grouped!.length + 1, // +1 for header
              itemBuilder: (context, index) {
                if (index == 0) return _buildHeader();
                final entry = _grouped!.entries.elementAt(index - 1);
                return _DateSection(
                  dateLabel: entry.key,
                  suggestions: entry.value,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
      child: Row(
        children: [
          Text('共 ${_grouped!.values.expand((l) => l).length} 条建议',
              style: TextStyle(fontSize: 12, color: C.scheme.onSurface.withAlpha(120))),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.help_outline, size: 18, color: C.scheme.onSurface.withAlpha(100)),
            onPressed: () => setState(() => _showHelp = !_showHelp),
            tooltip: '建议是什么？',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildHelpPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.scheme.tertiaryContainer.withAlpha(50),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('💡 关于建议', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: C.scheme.onSurface)),
          const SizedBox(height: 6),
          Text('${petOverlayController.petSelfRef}会根据你的互动习惯、时间和场景，\n主动给出不同级别的建议。\n这些都自动发生，无需手动操作。',
              style: TextStyle(fontSize: 12, color: C.scheme.onSurface.withAlpha(180), height: 1.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _levelChip(SuggestionLevel.l1, '💬', '轻提醒', '闲聊、心情表达'),
            _levelChip(SuggestionLevel.l2, '👀', '场景感知', '基于上下文的观察'),
            _levelChip(SuggestionLevel.l3, '💡', '深度建议', '基于记忆的个性化建议'),
            _levelChip(SuggestionLevel.l4, '🔔', '重要提醒', '长时间未互动时的关心'),
          ]),
        ],
      ),
    );
  }

  Widget _levelChip(SuggestionLevel level, String icon, String title, String desc) {
    return Chip(
      avatar: Text(icon, style: const TextStyle(fontSize: 13)),
      label: Text('$title：$desc', style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🐱', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 20),
            Text('还没有建议',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: C.scheme.onSurface)),
            const SizedBox(height: 10),
            Text(
              '${petOverlayController.petSelfRef}的建议会在以下时机自动出现：\n'
              '• 和你互动后，${petOverlayController.petSelfRef}会给出反应\n'
              '• 在特定时间，${petOverlayController.petSelfRef}会主动关心\n'
              '• 随着相处时间增长，建议会更个性化\n'
              '\n'
              '过一会再来看吧~',
              style: TextStyle(fontSize: 13, height: 1.7, color: C.scheme.onSurface.withAlpha(170)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('刷新看看'),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────
// _DateSection — 日期分组
// ────────────────────────────────────────

class _DateSection extends StatelessWidget {
  final String dateLabel;
  final List<Suggestion> suggestions;

  const _DateSection({required this.dateLabel, required this.suggestions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              Text(
                dateLabel == '今天' ? '☀️' : dateLabel == '昨天' ? '🌙' : '📅',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 6),
              Text(dateLabel,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              Text('${suggestions.length}条',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant.withAlpha(150))),
            ],
          ),
        ),
        ...suggestions.map((s) => _SuggestionBubble(suggestion: s)),
      ],
    );
  }
}

// ────────────────────────────────────────
// _SuggestionBubble — 单条建议
// ────────────────────────────────────────

class _SuggestionBubble extends StatelessWidget {
  final Suggestion suggestion;

  const _SuggestionBubble({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = suggestion.level == SuggestionLevel.l1;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isCompact ? 3 : 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_levelIcon(suggestion.level), style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: isCompact ? 8 : 12),
              decoration: BoxDecoration(
                color: _bubbleColor(suggestion.level, theme),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(suggestion.text,
                      style: TextStyle(fontSize: isCompact ? 13 : 14,
                          color: theme.colorScheme.onSurface, height: 1.45)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(_formatTime(suggestion.createdAt),
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                      if (suggestion.source.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(suggestion.source,
                              style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text(_levelLabel(suggestion.level),
                          style: TextStyle(fontSize: 10, color: _levelColor(suggestion.level))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _levelIcon(SuggestionLevel level) => switch (level) {
    SuggestionLevel.l1 => '💬', SuggestionLevel.l2 => '👀',
    SuggestionLevel.l3 => '💡', SuggestionLevel.l4 => '🔔',
  };

  String _levelLabel(SuggestionLevel level) => switch (level) {
    SuggestionLevel.l1 => '轻提醒', SuggestionLevel.l2 => '场景感知',
    SuggestionLevel.l3 => '深度建议', SuggestionLevel.l4 => '重要提醒',
  };

  Color _levelColor(SuggestionLevel level) => switch (level) {
    SuggestionLevel.l1 => Colors.grey,    SuggestionLevel.l2 => Colors.blueGrey,
    SuggestionLevel.l3 => Colors.teal,    SuggestionLevel.l4 => Colors.deepOrange,
  };

  Color _bubbleColor(SuggestionLevel level, ThemeData theme) {
    final base = theme.colorScheme.surfaceContainerHighest;
    return switch (level) {
      SuggestionLevel.l1 => base.withValues(alpha: 0.5),
      SuggestionLevel.l2 => base.withValues(alpha: 0.7),
      SuggestionLevel.l3 => base.withValues(alpha: 0.9),
      SuggestionLevel.l4 => base.withValues(alpha: 0.85),
    };
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(time.year, time.month, time.day);
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    if (thatDay == today) return '$hour:$minute';
    final yesterday = today.subtract(const Duration(days: 1));
    if (thatDay == yesterday) return '昨天 $hour:$minute';
    return '${time.month}月${time.day}日 $hour:$minute';
  }
}
