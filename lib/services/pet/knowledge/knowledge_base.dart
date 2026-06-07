// Flutter 3.24 / Dart 3.5
import '../../../pet/pet_persona.dart';
import 'models/diary_entry.dart';
import 'models/memory_entry.dart';
import 'models/user_profile.dart';
import 'diary/diary_repository.dart';
import 'diary/diary_store.dart';
import 'memory/memory_repository.dart';
import 'memory/memory_store.dart';

/// 上下文深度（用户可控）
enum ContextDepth { minimal, standard, deep }

/// 建议层级（D8 定义，此处引用）
enum SuggestionLevel { l1, l2, l3, l4 }

/// D8 决策上下文：喂给 Decision LLM 的聚合信息
class DecisionContext {
  final String summary;          // 上下文摘要文本（~0-200 tok）
  final List<String> interests;  // 用户兴趣标签
  final Map<String, double> habits; // 习惯权重
  final List<String> facts;      // 相关记忆事实
  final DateTime? lastInteraction;

  const DecisionContext({
    this.summary = '',
    this.interests = const [],
    this.habits = const {},
    this.facts = const [],
    this.lastInteraction,
  });

  /// 格式化为一小段可注入 LLM prompt 的文本
  String toPromptFragment() {
    final sb = StringBuffer();
    if (summary.isNotEmpty) sb.writeln(summary);
    if (interests.isNotEmpty) {
      sb.writeln('主人兴趣：${interests.take(3).join('、')}。');
    }
    if (habits.isNotEmpty) {
      final habitDesc = habits.entries
          .take(3)
          .map((e) => _habitLabel(e.key, e.value))
          .join('；');
      sb.writeln('主人习惯：$habitDesc。');
    }
    if (facts.isNotEmpty) {
      for (final f in facts.take(3)) {
        sb.writeln('- $f');
      }
    }
    return sb.toString().trim();
  }

  String _habitLabel(String key, double weight) {
    final level = weight > 0.7 ? '高' : weight > 0.4 ? '中' : '低';
    final name = switch (key) {
      'lateNight' => '深夜活动',
      'longWork' => '长时间工作',
      'longCoding' => '长时间编码',
      'coffee' => '喝咖啡',
      _ => key,
    };
    return '$name($level)';
  }
}

/// 统一知识库门面
/// D8 的 ContextCollector 只与此类对话
class KnowledgeBase {
  final DiaryStore diaryStore;
  final MemoryStore memoryStore;
  final IDiaryRepository _diaryRepo;
  final IMemoryRepository _memoryRepo;
  PetPersona? _persona;

  KnowledgeBase({
    required this.diaryStore,
    required this.memoryStore,
    required IDiaryRepository diaryRepo,
    required IMemoryRepository memoryRepo,
    PetPersona? persona,
  })  : _diaryRepo = diaryRepo,
        _memoryRepo = memoryRepo,
        _persona = persona {
    diaryStore.setPersonaPrompt(
        persona?.buildSystemPrompt() ?? PetPersona().buildSystemPrompt());
  }

  /// 更新当前人格
  void updatePersona(PetPersona persona) {
    _persona = persona;
    diaryStore.setPersonaPrompt(persona.buildSystemPrompt());
  }

  // ═══ D8 决策上下文 ═══

  Future<DecisionContext> getDecisionContext({
    required SuggestionLevel level,
    ContextDepth userDepth = ContextDepth.standard,
  }) async {
    // 实际深度 = min(用户偏好, 建议层级最低要求)
    final depth = _resolveDepth(level, userDepth);

    return switch (depth) {
      ContextDepth.minimal => await _buildMinimal(),
      ContextDepth.standard => await _buildStandard(),
      ContextDepth.deep => await _buildDeep(),
    };
  }

  ContextDepth _resolveDepth(SuggestionLevel level, ContextDepth userDepth) {
    // L1 只需要 minimal，L2 需要 standard，L3-L4 需要 deep
    final required = switch (level) {
      SuggestionLevel.l1 => ContextDepth.minimal,
      SuggestionLevel.l2 => ContextDepth.standard,
      SuggestionLevel.l3 || SuggestionLevel.l4 => ContextDepth.deep,
    };
    // 取较低的（省 token）
    const depths = ContextDepth.values;
    final userIdx = depths.indexOf(userDepth);
    final requiredIdx = depths.indexOf(required);
    final resolved = userIdx < requiredIdx ? userDepth : required;
    return resolved;
  }

  Future<DecisionContext> _buildMinimal() async {
    final now = DateTime.now();
    final todayEvents = await _diaryRepo.loadByDate(now);
    final timeDesc = _timeOfDay(now.hour);

    return DecisionContext(
      summary: '现在是$timeDesc。今天主人互动了${todayEvents.length}次。',
      lastInteraction: todayEvents.lastOrNull?.date,
    );
  }

  Future<DecisionContext> _buildStandard() async {
    final minimal = await _buildMinimal();
    final profile = await memoryStore.buildProfileAsync();
    final recentMemories =
        (await _memoryRepo.loadAll()).where((m) => m.importance > 0.4).take(5);

    return DecisionContext(
      summary: minimal.summary,
      interests: profile.interests,
      habits: profile.habitWeights,
      facts: recentMemories.map((m) => m.content).toList(),
      lastInteraction: minimal.lastInteraction,
    );
  }

  Future<DecisionContext> _buildDeep() async {
    final standard = await _buildStandard();
    final recentDiary = await _diaryRepo.loadRecent(days: 7);
    final allMemories = await _memoryRepo.loadAll();
    final topMemories = [...allMemories]
      ..sort((a, b) => b.importance.compareTo(a.importance));

    // 追加本周日记摘要
    final sb = StringBuffer(standard.summary);
    final diaryHighlights = recentDiary
        .where((e) => e.type == DiaryEntryType.highlight)
        .take(3)
        .toList();
    if (diaryHighlights.isNotEmpty) {
      sb.writeln();
      sb.writeln('近期重要事件：');
      for (final h in diaryHighlights) {
        sb.writeln('- ${h.content}');
      }
    }

    return DecisionContext(
      summary: sb.toString().trim(),
      interests: standard.interests,
      habits: standard.habits,
      facts: topMemories.take(5).map((m) => m.content).toList(),
      lastInteraction: standard.lastInteraction,
    );
  }

  // ═══ 检索 ═══

  Future<List<MemoryEntry>> searchMemories(String query, {int limit = 5}) async {
    final results = await _memoryRepo.search(query);
    results.sort((a, b) => b.importance.compareTo(a.importance));
    return results.take(limit).toList();
  }

  // ═══ 用户画像 ═══

  Future<UserProfile> getUserProfile() => memoryStore.buildProfileAsync();

  // ═══ 日记查询 ═══

  Future<List<DiaryEntry>> getTodayDiary() => diaryStore.loadToday();

  Future<List<DiaryEntry>> getRecentDiary({int days = 7}) =>
      _diaryRepo.loadRecent(days: days);

  /// 删除单条日记
  Future<void> deleteDiaryEntry(String id) => _diaryRepo.delete(id);

  // ═══ Persona ── ═══

  String buildSystemPrompt() {
    return _persona?.buildSystemPrompt() ?? PetPersona().buildSystemPrompt();
  }

  // ═══ 工具 ═══

  String _timeOfDay(int hour) {
    if (hour < 6) return '凌晨';
    if (hour < 9) return '早上';
    if (hour < 12) return '上午';
    if (hour < 14) return '中午';
    if (hour < 18) return '下午';
    if (hour < 21) return '傍晚';
    return '晚上';
  }

  void dispose() {
    diaryStore.dispose();
    memoryStore.dispose();
  }
}
