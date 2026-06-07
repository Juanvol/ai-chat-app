// Flutter 3.24 / Dart 3.5
import '../pet_logger.dart';
import '../knowledge/knowledge_base.dart' as kb;
import '../unlock/unlock_store.dart';
import 'budget_gate.dart';
import 'disturb_gate.dart';
import 'models/suggestion.dart';
import 'suggestion_store.dart';

/// 主动建议引擎 — 五道门协作器
///
/// **门控链（shouldSuggest 内按序执行）：**
/// 0. DisturbGate.refresh() — 刷新熔断器状态
/// 1. DisturbGate.isSuppressed — 熔断静默中
/// 2. DisturbGate.isLateNight — 深夜概率降频
/// 3. UnlockStore.isUnlocked — 渐进解锁
/// 4. BudgetGate.canAfford — Token 预算
///
/// **上下文深度由 getAllowedLevel()（预算∩解锁）决定。**
class SuggestionEngine {
  final kb.KnowledgeBase _kb;
  final BudgetGate _budget;
  final SuggestionStore _store;
  final UnlockStore? _unlockStore;
  final DisturbGate _disturb;

  SuggestionEngine({
    required kb.KnowledgeBase knowledgeBase,
    BudgetGate? budgetGate,
    SuggestionStore? store,
    UnlockStore? unlockStore,
    DisturbGate? disturbGate,
  })  : _kb = knowledgeBase,
        _budget = budgetGate ?? BudgetGate(),
        _store = store ?? SuggestionStore(),
        _unlockStore = unlockStore,
        _disturb = disturbGate ?? DisturbGate();

  /// 公开知识库（供外部读取用户画像等）
  kb.KnowledgeBase get knowledgeBase => _kb;

  // ═══ D8k 情绪映射 ═══

  /// 建议层级 → (表情, 动画) 映射
  static ({String emoji, String anim}) emotionForLevel(SuggestionLevel level) =>
      switch (level) {
        SuggestionLevel.l1 => (emoji: '😊', anim: 'idle'),
        SuggestionLevel.l2 => (emoji: '🤔', anim: 'wave'),
        SuggestionLevel.l3 => (emoji: '🧐', anim: 'talking'),
        SuggestionLevel.l4 => (emoji: '📋', anim: 'jump'),
      };

  /// 建议发布后回调（供 PetOverlayController 同步情绪动画到 Kotlin 层）
  void Function(SuggestionLevel level)? onSuggestionPublished;

  // ═══ 公开访问器 ═══

  BudgetGate get budget => _budget;
  DisturbGate get disturb => _disturb;
  SuggestionStore get store => _store;

  // ═══ 上下文构建 ═══

  /// 构建 LLM 决策上下文 prompt
  ///
  /// 上下文深度由 getAllowedLevel()（预算 ∩ 解锁）决定，
  /// 确保未解锁层级不会浪费 Token 收集深层上下文。
  Future<String> buildDecisionContext() async {
    final allowedLevel = await getAllowedLevel();

    // 上下文深度 ← 允许层级（预算 ∩ 解锁）
    final depth = switch (allowedLevel) {
      SuggestionLevel.l4 || SuggestionLevel.l3 => kb.ContextDepth.deep,
      SuggestionLevel.l2 => kb.ContextDepth.standard,
      SuggestionLevel.l1 => kb.ContextDepth.minimal,
    };

    // 映射到 KnowledgeBase 的 SuggestionLevel 枚举
    final kbLevel = kb.SuggestionLevel.values[allowedLevel.index];

    final ctx = await _kb.getDecisionContext(
      level: kbLevel,
      userDepth: depth,
    );

    final sb = StringBuffer();
    sb.writeln('【当前上下文】');
    sb.writeln(ctx.toPromptFragment());

    // 解锁进度
    if (_unlockStore != null) {
      final days = _unlockStore.daysSinceFirstInteraction;
      sb.writeln(
          '陪伴天数：第${days + 1}天，当前解锁：${_unlockStore.unlockedLevel.name}。');
      final next = _unlockStore.nextUnlock;
      if (next != null) {
        sb.writeln('${next.days}天后将解锁${next.label}。');
      }
    }

    // 预算信息
    final remaining = await _budget.getRemaining();
    final budgetInfo = await _budget.getTierLabel();
    sb.writeln('预算档位：$budgetInfo（剩余 $remaining tok）');

    PetLogger().trace('SuggestionEngine',
        'buildDecisionContext: depth=$depth budget=$budgetInfo unlock=${_unlockStore?.unlockedLevel.name}');
    return sb.toString().trim();
  }

  // ═══ 门控链 ═══

  /// 判断当前是否允许生成指定层级的建议
  ///
  /// **四道门按序检查：**
  /// 0. 刷新熔断器状态（解除过期静默 + 跨天重置）
  /// 1. 熔断静默 → 直接拒绝
  /// 2. 深夜降频 → 2/3 概率拒绝
  /// 3. 渐进解锁 → 层级未解锁则拒绝
  /// 4. Token 预算 → 余额不足则拒绝
  Future<bool> shouldSuggest(SuggestionLevel level) async {
    // ── 0. 刷新熔断器状态 ──
    _disturb.refresh();

    // ── 1. 熔断静默 ──
    if (_disturb.isSuppressed) {
      PetLogger().trace('SuggestionEngine',
          'gate: circuit breaker (${_disturb.suppressRemainingSeconds}s left)');
      return false;
    }

    // ── 2. 深夜降频（~1/3 通过）──
    if (_disturb.isLateNight) {
      if (DateTime.now().millisecondsSinceEpoch % 3 != 0) {
        PetLogger().trace('SuggestionEngine', 'gate: late-night skip');
        return false;
      }
    }

    // ── 3. 渐进解锁 ──
    if (_unlockStore != null && !_unlockStore.isUnlocked(level)) {
      PetLogger().trace('SuggestionEngine',
          'gate: ${level.name} locked (day ${_unlockStore.daysSinceFirstInteraction})');
      return false;
    }

    // ── 4. 层级 + 预算 ──
    final allowed = await getAllowedLevel();
    if (UnlockStore.unlockTier(level) > UnlockStore.unlockTier(allowed)) {
      PetLogger().trace('SuggestionEngine',
          'gate: ${level.name} exceeds allowed ${allowed.name}');
      return false;
    }
    if (!await _budget.canAfford(level.estimatedTokens)) {
      PetLogger().trace('SuggestionEngine',
          'gate: cannot afford ${level.estimatedTokens} tok');
      return false;
    }

    return true;
  }

  /// 获取当前允许的最高建议层级（预算 ∩ 解锁）
  Future<SuggestionLevel> getAllowedLevel() async {
    final budgetLevel = await _budget.getAllowedLevel();
    if (_unlockStore == null) return budgetLevel;

    final unlockLevel = _unlockStore.unlockedLevel;
    final budgetTier = UnlockStore.unlockTier(budgetLevel);
    final unlockTier = UnlockStore.unlockTier(unlockLevel);
    return budgetTier <= unlockTier ? budgetLevel : unlockLevel;
  }

  // ═══ 持久化 ═══

  /// 记录一条建议到持久化存储（由 PetAgentCore._publishAction 调用）
  ///
  /// 返回 true = 新建议已写入，false = 重复/空内容。
  /// 写入成功后通知 DisturbGate 更新频率计数。
  Future<bool> recordSuggestion({
    required String text,
    SuggestionLevel level = SuggestionLevel.l1,
    String topic = '',
    String source = '',
  }) async {
    if (text.isEmpty) return false;

    final suggestion = Suggestion(
      level: level,
      text: text,
      topic: topic,
      source: source,
    );

    final added = await _store.add(suggestion);
    if (added) {
      PetLogger().trace(
          'SuggestionEngine', 'recorded L${level.name} "$text"');
      _disturb.recordSuggestion();
      // D8k: 通知情绪同步
      onSuggestionPublished?.call(level);
    }
    return added;
  }

  /// 记录用户解除气泡（互动打断建议气泡）
  void recordDismissal() => _disturb.recordDismissal();

  // ═══ 生命周期 ═══

  void dispose() {
    _store.dispose();
  }
}
