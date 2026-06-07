// Flutter 3.24 / Dart 3.5
import '../../pet_logger.dart';
import '../../pet_token_service.dart';
import '../models/diary_entry.dart';
import '../models/memory_entry.dart';
import '../models/user_profile.dart';
import 'memory_repository.dart';
import 'memory_extractor.dart';
import 'memory_organizer.dart';
import '../diary/diary_repository.dart';

/// 记忆领域服务：提取/整理/过期/用户 CRUD
class MemoryStore {
  final IMemoryRepository _repo;
  final MemoryExtractor _extractor;
  final MemoryOrganizer _organizer;
  final IDiaryRepository? _diaryRepo; // 用于检索30天内事件（稀有检测）
  final PetTokenService? _tokenService;

  DateTime? _lastOrganizeAt;

  MemoryStore({
    required IMemoryRepository repo,
    MemoryExtractor? extractor,
    MemoryOrganizer? organizer,
    IDiaryRepository? diaryRepo,
    PetTokenService? tokenService,
  })  : _repo = repo,
        _extractor = extractor ?? MemoryExtractor(),
        _organizer = organizer ?? MemoryOrganizer(),
        _diaryRepo = diaryRepo,
        _tokenService = tokenService;

  // ═══ 从日记事件提取记忆 ═══

  /// DiaryStore 调用此方法处理新事件
  Future<void> extractFrom(DiaryEntry event) async {
    final existingMemories = await _repo.loadAll();
    final lateNightCount = _countLateNightThisMonth(event.date, existingMemories);
    final isRare = await _isRareIn30Days(event, existingMemories);

    final entry = _extractor.extract(
      event,
      existingMemories: existingMemories,
      lateNightCountThisMonth: lateNightCount,
      isRareIn30Days: isRare,
    );

    if (entry != null) {
      await _repo.save(entry);
      PetLogger().trace('MemoryStore',
          'extracted: ${entry.tag.name} → ${entry.content}');
    }
  }

  // ═══ LLM 整理（Phase 2 实现） ═══

  /// 每1天触发一次 LLM 批量整理（测验版）
  /// [force] 为 true 时跳过冷却检查（手动触发）
  /// 返回 (更新的条目列表, 删除的ID列表)；null 表示跳过
  Future<({List<MemoryEntry> updated, List<String> deleted})?> organizeIfNeeded({bool force = false}) async {
    if (!force && _lastOrganizeAt != null &&
        DateTime.now().difference(_lastOrganizeAt!).inDays < 1) {
      return null;
    }

    int remaining = 0;
    if (_tokenService != null) {
      remaining = await _tokenService.getBudgetRemaining();
    }
    if (remaining < 150) {
      PetLogger().trace('MemoryStore',
          'organizeIfNeeded skip: budget $remaining < 150');
      return null;
    }

    final existing = await _repo.loadAll();
    final result = await _organizer.organize(
      existingMemories: existing,
      remainingBudget: remaining,
    );

    if (result.toUpdate.isNotEmpty) {
      await _repo.saveAll(result.toUpdate);
      PetLogger().info('MemoryStore',
          'organize: updated ${result.toUpdate.length} memories');
    }

    for (final id in result.toDelete) {
      // 保存被删除记忆的内容，用于UI展示
      await _repo.delete(id);
      PetLogger().info('MemoryStore', 'organize: deleted $id');
    }

    _lastOrganizeAt = DateTime.now();
    return (updated: result.toUpdate, deleted: result.toDelete);
  }

  // ═══ 用户 CRUD ═══

  /// 用户手动添加记忆
  Future<MemoryEntry> addMemory(String content, MemoryTag tag) async {
    final entry = MemoryEntry(
      id: 'mem_user_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      tag: tag,
      content: content,
      importance: 0.5,
      createdAt: DateTime.now(),
      source: MemorySource.rule,
    );
    await _repo.save(entry);
    PetLogger().trace('MemoryStore', 'user add: $content');
    return entry;
  }

  /// 用户编辑记忆
  Future<void> updateMemory(
    String id, {
    String? content,
    double? importance,
    MemoryTag? tag,
  }) async {
    final list = await _repo.loadAll();
    final existing = list.where((m) => m.id == id).firstOrNull;
    if (existing == null) {
      PetLogger().warn('MemoryStore', 'updateMemory: $id not found');
      return;
    }
    final updated = existing.copyWith(
      content: content,
      importance: importance,
      tag: tag,
      updatedAt: DateTime.now(),
    );
    await _repo.update(id, updated);
    PetLogger().trace('MemoryStore', 'user update: ${updated.content}');
  }

  /// 用户删除记忆
  Future<void> deleteMemory(String id) async {
    await _repo.delete(id);
    PetLogger().trace('MemoryStore', 'user delete: $id');
  }

  // ═══ 查询 ═══

  Future<List<MemoryEntry>> loadAll({MemoryTag? tag}) => _repo.loadAll(tag: tag);

  Future<List<MemoryEntry>> search(String keyword) => _repo.search(keyword);

  // ═══ 用户画像聚合（纯规则，异步） ═══

  Future<UserProfile> buildProfileAsync() async {
    final all = await _repo.loadAll();

    // 兴趣标签：tag=interest + importance > 0.3
    final interests = all
        .where((m) => m.tag == MemoryTag.interest && m.importance > 0.3)
        .map((m) => m.content.replaceAll('主人对', '').replaceAll('感兴趣', ''))
        .toSet()
        .toList();

    // 习惯权重：tag=habit，按重要性加权
    final habitWeights = <String, double>{};
    for (final m in all.where((m) => m.tag == MemoryTag.habit)) {
      final key = _extractHabitKey(m.content);
      habitWeights[key] =
          (habitWeights[key] ?? 0.0) + m.importance * 0.5.clamp(0.0, 1.0);
    }

    // 近期话题：tag=event + 按时间排序 top 10
    final recentTopics = all
        .where((m) => m.tag == MemoryTag.event || m.tag == MemoryTag.fact)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final topics = recentTopics.take(10).map((m) => m.content).toList();

    return UserProfile(
      interests: interests,
      habitWeights: habitWeights,
      recentTopics: topics,
      updatedAt: DateTime.now(),
    );
  }

  // ═══ 导出/导入 ═══

  Future<String> exportJson() async {
    final all = await _repo.loadAll();
    return '[${all.map((m) => m.toJson()).join(',')}]';
  }

  Future<void> importJson(String json) async {
    // 不实现完整解析，留 Phase 2
    PetLogger().warn('MemoryStore', 'importJson not yet implemented');
  }

  // ═══ 内部工具 ═══

  /// 本月深夜活动计数
  int _countLateNightThisMonth(DateTime dt, List<MemoryEntry> existing) {
    final monthStart = DateTime(dt.year, dt.month, 1);
    return existing
        .where((m) =>
            m.tag == MemoryTag.habit &&
            m.content.contains('深夜') &&
            m.createdAt.isAfter(monthStart))
        .length;
  }

  /// 检查事件类型在30天内是否稀有
  Future<bool> _isRareIn30Days(
      DiaryEntry event, List<MemoryEntry> existing) async {
    final type = event.sourceType;
    if (type == null) return false;

    // 高频事件不在稀有检测范围内
    const commonTypes = {'tap', 'talk'};
    if (commonTypes.contains(type)) return false;

    final cutoff = event.date.subtract(const Duration(days: 30));
    // 检查记忆库
    final recentMentions = existing.where((m) =>
        m.sourceDiaryId != null &&
        m.createdAt.isAfter(cutoff) &&
        m.content.contains(type)).length;
    if (recentMentions > 0) return false;
    // 检查日记库
    final diaryRepo = _diaryRepo;
    if (diaryRepo != null) {
      final recentDiary = await diaryRepo.loadRecent(days: 30);
      final sameType = recentDiary
          .where((d) => d.sourceType == type && d.id != event.id)
          .length;
      return sameType == 0;
    }
    return true;
  }

  String _extractHabitKey(String content) {
    // 简单关键词提取：从内容中取核心名词
    if (content.contains('深夜')) return 'lateNight';
    if (content.contains('工作')) return 'longWork';
    if (content.contains('编码') || content.contains('写代码')) return 'longCoding';
    if (content.contains('咖啡')) return 'coffee';
    return 'other';
  }

  void dispose() {
    _extractor.dispose();
  }
}
