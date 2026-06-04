// Flutter 3.24 / Dart 3.5
import 'dart:math';
import '../models/diary_entry.dart';
import '../models/memory_entry.dart';

/// 规则驱动的记忆提取器（纯规则，无 LLM，零 token 消耗）
class MemoryExtractor {
  final Random _rng = Random();

  /// 用户兴趣关键词 → 标签映射
  static const Map<String, String> _interestKeywords = {
    // 编程
    'rust': 'Rust',
    'python': 'Python',
    'java': 'Java',
    'flutter': 'Flutter',
    'dart': 'Dart',
    'go': 'Go',
    '编程': '编程',
    '代码': '编程',
    '算法': '算法',
    'bug': '编程',
    'debug': '编程',
    '前端': '前端开发',
    '后端': '后端开发',
    'ai': 'AI',
    '人工智能': 'AI',
    '机器学习': 'AI',
    // 游戏
    '游戏': '游戏',
    'steam': '游戏',
    'switch': '游戏',
    'ps5': '游戏',
    '独立游戏': '独立游戏',
    // 生活
    '咖啡': '咖啡',
    '奶茶': '奶茶',
    '茶': '茶',
    '美食': '美食',
    '健身': '健身',
    '跑步': '运动',
    '运动': '运动',
    '旅行': '旅行',
    '摄影': '摄影',
    // 音乐
    '音乐': '音乐',
    '歌': '音乐',
    '钢琴': '钢琴',
    '吉他': '吉他',
    // 阅读
    '书': '阅读',
    '阅读': '阅读',
    '小说': '阅读',
    // 工作
    '开会': '工作',
    '加班': '工作',
    '项目': '工作',
  };

  /// 深夜时段
  static bool _isLateNight(int hour) => hour >= 1 && hour <= 5;

  /// 从日记事件中提取记忆（返回 null 表示无新记忆可提）
  MemoryEntry? extract(
    DiaryEntry event, {
    required List<MemoryEntry> existingMemories,
    required int lateNightCountThisMonth,
    required bool isRareIn30Days,
  }) {
    final type = event.sourceType ?? '';
    final content = event.content;
    final hour = event.date.hour;

    // ── 1. 深夜活动 → habit ──
    if (type == 'tap' && _isLateNight(hour) && lateNightCountThisMonth >= 5) {
      final exists = existingMemories.any(
          (m) => m.tag == MemoryTag.habit && m.content.contains('深夜'));
      if (!exists) {
        return MemoryEntry(
          id: _genId('habit_late', event.date),
          tag: MemoryTag.habit,
          content: '主人经常深夜工作/活动（凌晨${hour}点还在活跃）',
          importance: 0.6,
          createdAt: event.date,
          source: MemorySource.rule,
          sourceDiaryId: event.id,
        );
      }
    }

    // ── 2. 对话关键词 → interest ──
    if (type == 'talk' || type == 'suggestion') {
      for (final kw in _interestKeywords.keys) {
        if (content.contains(kw)) {
          final label = _interestKeywords[kw]!;
          final exists = existingMemories
              .any((m) => m.tag == MemoryTag.interest && m.content.contains(label));
          if (!exists) {
            return MemoryEntry(
              id: _genId('interest_$kw', event.date),
              tag: MemoryTag.interest,
              content: '主人对$label感兴趣',
              importance: 0.5,
              createdAt: event.date,
              source: MemorySource.rule,
              sourceDiaryId: event.id,
            );
          }
        }
      }
    }

    // ── 3. 建议(L3+) → event 直接写入 ──
    if (type == 'suggestion') {
      return MemoryEntry(
        id: _genId('event_sug', event.date),
        tag: MemoryTag.event,
        content: content,
        importance: 0.5,
        createdAt: event.date,
        source: MemorySource.rule,
        sourceDiaryId: event.id,
      );
    }

    // ── 4. 稀有互动（30天内首次）→ fact ──
    if (isRareIn30Days) {
      return MemoryEntry(
        id: _genId('rare_$type', event.date),
        tag: MemoryTag.fact,
        content: '主人第一次做了「$type」互动',
        importance: 0.4,
        createdAt: event.date,
        source: MemorySource.rule,
        sourceDiaryId: event.id,
      );
    }

    return null;
  }

  String _genId(String prefix, DateTime dt) =>
      'mem_${prefix}_${dt.microsecondsSinceEpoch.toRadixString(36)}_${_rng.nextInt(9999)}';

  void dispose() {}
}
