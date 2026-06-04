// Flutter 3.24 / Dart 3.5
import 'dart:math';
import '../../pet_logger.dart';
import '../models/diary_entry.dart';
import 'diary_repository.dart';

/// 日记领域服务：事件记录 + 高亮检测 + 日总结调度
class DiaryStore {
  final IDiaryRepository _repo;
  final void Function(DiaryEntry event)? onEventRecorded;

  /// 高亮检测用的滑动窗口（同一日内的近期事件）
  final List<DiaryEntry> _recentEventsByDay = [];

  DiaryStore({
    required IDiaryRepository repo,
    this.onEventRecorded,
  }) : _repo = repo;

  // ═══ 事件 → 内容映射（与旧 PetDiaryService 保持一致） ═══

  static (String content, String mood) _eventContent(
      String type, String? detail) {
    return switch (type) {
      'tap' => ('被主人轻轻戳了一下~', '😊'),
      'pet' => ('被主人温柔地抚摸了好几下，舒服喵~ 💕', '😸'),
      'feed' => ('吃了一顿美味大餐~', '😋'),
      'play' => ('和主人愉快地玩了会儿~', '😸'),
      'talk' => ('和主人聊了会天~', '💬'),
      'sleep' => ('糯糯睡着了...zzZ', '💤'),
      'wake' => ('糯糯醒啦，又是元气满满的一天~', '😸'),
      'longPress' => ('享受了主人给的零食，好吃好吃~ 😋', '😋'),
      'suggestion' => (detail ?? '给了主人一个小建议', '💡'),
      'lowEnergy' => ('能量不足，糯糯好累...', '😞'),
      'lowHunger' => ('肚子饿了，想吃东西...', '🍖'),
      _ => (detail ?? '发生了某件事', '📝'),
    };
  }

  // ═══ 主入口：记录事件 ═══

  /// 记录一条互动事件，自动写日记条目
  Future<DiaryEntry> recordEvent(String type, {String? detail}) async {
    final now = DateTime.now();
    final (content, mood) = _eventContent(type, detail);

    final entry = DiaryEntry(
      id: _genId(type, now),
      type: DiaryEntryType.event,
      content: content,
      mood: mood,
      sourceType: type,
      date: now,
    );

    await _repo.save(entry);
    PetLogger().trace('DiaryStore', 'event: $type → $content');

    // 高亮检测
    _updateRecentWindow(entry);
    final highlight = _detectHighlight(entry);
    if (highlight != null) {
      await _repo.save(highlight);
      PetLogger().trace('DiaryStore', 'highlight: ${highlight.content}');
    }

    // 通知 MemoryStore 提取记忆
    onEventRecorded?.call(entry);

    return entry;
  }

  // ═══ 高亮检测（纯规则，无 LLM） ═══

  /// 维护当日事件滑动窗口（最近 20 条）
  void _updateRecentWindow(DiaryEntry entry) {
    final today = entry.dateKey;
    _recentEventsByDay.removeWhere((e) => e.dateKey != today);
    _recentEventsByDay.add(entry);
    if (_recentEventsByDay.length > 20) {
      _recentEventsByDay.removeAt(0);
    }
  }

  DiaryEntry? _detectHighlight(DiaryEntry event) {
    // 1. 稀有互动：检查过去30天是否有同类型事件
    //    （由调用方传入30天内事件计数，此处简化为本地检查）
    //    实际实现中由 DiaryStore 持有近期事件的缓存

    // 2. 深夜活动：凌晨 1-5 点
    final hour = event.date.hour;
    if (hour >= 1 && hour <= 5) {
      final todayLateNight = _recentEventsByDay
          .where((e) =>
              e.date.hour >= 1 &&
              e.date.hour <= 5 &&
              e.id != event.id)
          .length;
      if (todayLateNight == 0) {
        // 今日首次深夜活动
        return DiaryEntry(
          id: _genId('highlight_late', event.date),
          type: DiaryEntryType.highlight,
          content: '凌晨${hour}点主人还在活动...糯糯默默地陪着~ 🌙',
          mood: '🌙',
          sourceType: 'highlight',
          date: event.date,
        );
      }
    }

    // 3. 连续长时间无交互（3h+）：由调用方传入 idle 时长
    //    这里作为扩展点预留，当前由 PetOverlayController 自行判断

    return null;
  }

  /// 检查是否有心情剧烈变化（由外部 Controller 调用，传入 mood 历史）
  Future<void> checkMoodDip(double currentMood, List<double> recentMoods) async {
    if (recentMoods.isEmpty) return;
    final avg = recentMoods.reduce((a, b) => a + b) / recentMoods.length;
    if (avg - currentMood >= 40) {
      final entry = DiaryEntry(
        id: _genId('highlight_mood', DateTime.now()),
        type: DiaryEntryType.highlight,
        content: '糯糯今天心情突然变差了...从${avg.toInt()}掉到${currentMood.toInt()}...是发生什么事了吗？ 😢',
        mood: '😢',
        sourceType: 'highlight',
        date: DateTime.now(),
      );
      await _repo.save(entry);
      onEventRecorded?.call(entry);
    }
  }

  // ═══ 日总结（Phase 2 实现） ═══

  /// 日总结占位：Phase 2 集成 LLM
  Future<DiaryEntry?> summarizeDay(DateTime date) async {
    // Phase 2: DiarySummarizer 调用 LLM
    // 此处返回 null 表示"未实现"
    return null;
  }

  // ═══ 查询 ═══

  Future<List<DiaryEntry>> loadToday() => _repo.loadByDate(DateTime.now());

  Future<List<DiaryEntry>> loadByDate(DateTime date) => _repo.loadByDate(date);

  Future<List<DiaryEntry>> loadRecent({int days = 7}) =>
      _repo.loadRecent(days: days);

  // ═══ 工具 ═══

  String _genId(String prefix, DateTime dt) =>
      '${prefix}_${dt.microsecondsSinceEpoch.toRadixString(36)}_${Random().nextInt(9999)}';

  void dispose() {
    _recentEventsByDay.clear();
  }
}
