// Flutter 3.24 / Dart 3.5
import 'dart:math';
import '../../pet_logger.dart';
import '../../pet_token_service.dart';
import '../../pet_overlay_host.dart';
import '../models/diary_entry.dart';
import 'diary_repository.dart';
import 'diary_summarizer.dart';

/// 日记领域服务：事件记录 + 高亮检测 + 日总结调度
class DiaryStore {
  final IDiaryRepository _repo;
  final void Function(DiaryEntry event)? onEventRecorded;
  final DiarySummarizer _summarizer;
  final PetTokenService? _tokenService;

  /// 高亮检测用的滑动窗口（同一日内的近期事件）
  final List<DiaryEntry> _recentEventsByDay = [];
  String _personaPrompt = '';

  /// 从 PersonaStore 读取自称，空则 fallback
  static String get petSelfRef {
    final ref = petOverlayController.personaStore?.persona.style.selfReference;
    return (ref != null && ref.isNotEmpty) ? ref : '糯糯';
  }
  /// 从 PersonaStore 读取名字，空则 fallback
  static String get petName {
    final n = petOverlayController.personaStore?.persona.name;
    return (n != null && n.isNotEmpty) ? n : '糯糯';
  }

  DiaryStore({
    required IDiaryRepository repo,
    this.onEventRecorded,
    DiarySummarizer? summarizer,
    PetTokenService? tokenService,
  })  : _repo = repo,
        _summarizer = summarizer ?? DiarySummarizer(),
        _tokenService = tokenService;

  // ═══ 事件 → 内容映射（与旧 PetDiaryService 保持一致） ═══

  static (String content, String mood) _eventContent(
      String type, String? detail) {
    return switch (type) {
      'tap' => ('被主人轻轻戳了一下~', '😊'),
      'pet' => ('被主人温柔地抚摸了好几下，舒服喵~ 💕', '😸'),
      'feed' => ('吃了一顿美味大餐~', '😋'),
      'play' => ('和主人愉快地玩了会儿~', '😸'),
      'talk' => ('和主人聊了会天~', '💬'),
      'sleep' => ('${DiaryStore.petSelfRef}睡着了...zzZ', '💤'),
      'wake' => ('${DiaryStore.petSelfRef}醒啦，又是元气满满的一天~', '😸'),
      'longPress' => ('享受了主人给的零食，好吃好吃~ 😋', '😋'),
      'suggestion' => (detail ?? '给了主人一个小建议', '💡'),
      'lowEnergy' => ('能量不足，${DiaryStore.petSelfRef}好累...', '😞'),
      'lowHunger' => ('肚子饿了，想吃东西...', '🍖'),
      'milestone' => (detail ?? '好感度达到新阶段！', '🎉'),
      'import' => (detail ?? '从对话中导入了记忆~', '📝'),
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
          content: '凌晨$hour点主人还在活动...${DiaryStore.petSelfRef}默默地陪着~ 🌙',
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
        content: '${DiaryStore.petSelfRef}今天心情突然变差了...从${avg.toInt()}掉到${currentMood.toInt()}...是发生什么事了吗？ 😢',
        mood: '😢',
        sourceType: 'highlight',
        date: DateTime.now(),
      );
      await _repo.save(entry);
      onEventRecorded?.call(entry);
    }
  }

  // ═══ 日总结（Phase 2 实现） ═══

  /// 日总结：LLM 驱动，21:00 自动触发 / 手动触发
  /// [force] 为 true 时删除旧总结重新生成
  Future<DiaryEntry?> summarizeDay(DateTime date, {bool force = false}) async {
    final dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final todayEvents = await _repo.loadByDate(date);

    if (!force) {
      final existing = todayEvents
          .where((e) => e.type == DiaryEntryType.summary)
          .firstOrNull;
      if (existing != null) return existing;
    } else {
      // 删除旧总结
      for (final e in todayEvents.where((e) => e.type == DiaryEntryType.summary)) {
        await _repo.delete(e.id);
      }
    }

    final remaining =
        (await _tokenService?.getBudgetRemaining()) ?? 999999;

    final summary = await _summarizer.summarize(
      dateKey: dateKey,
      todayEvents: todayEvents,
      remainingBudget: remaining,
      personaPrompt: _personaPrompt,
    );

    if (summary != null) {
      await _repo.save(summary);
      PetLogger().trace('DiaryStore', 'summary: ${summary.content}');
    }

    return summary;
  }

  void setPersonaPrompt(String prompt) {
    _personaPrompt = prompt;
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
