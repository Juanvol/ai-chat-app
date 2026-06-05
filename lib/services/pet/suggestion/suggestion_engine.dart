// Flutter 3.24 / Dart 3.5
import '../pet_logger.dart';
import '../pet_token_service.dart';
import '../knowledge/knowledge_base.dart' as kb;
import 'budget_gate.dart';
import 'models/suggestion.dart';

/// 主动建议引擎 — 纯协调器，不持业务逻辑
///
/// 职责：
/// 1. 预算门控：根据剩余 Token 决定允许的建议层级
/// 2. 上下文聚合：从 KnowledgeBase 获取决策上下文
/// 3. 构建增强 prompt：合并上下文 + 预算信息 → 供 PetAgentCore 使用
class SuggestionEngine {
  final kb.KnowledgeBase _kb;
  final BudgetGate _budget;
  // 保留扩展点，后期使用
  // ignore: unused_field
  final PetTokenService _tokenService;

  SuggestionEngine({
    required kb.KnowledgeBase knowledgeBase,
    BudgetGate? budgetGate,
    PetTokenService? tokenService,
  })  : _kb = knowledgeBase,
        _budget = budgetGate ?? BudgetGate(),
        _tokenService = tokenService ?? PetTokenService.instance;

  BudgetGate get budget => _budget;

  /// 构建决策上下文 prompt — 供 PetAgentCore._evaluate() 注入
  ///
  /// 返回一段可直接拼接到决策 prompt 的文本。
  /// 根据预算自动降级上下文深度。
  Future<String> buildDecisionContext() async {
    final allowedLevel = await _budget.getAllowedLevel();

    // 预算 → 上下文深度映射
    final depth = switch (allowedLevel) {
      SuggestionLevel.l4 || SuggestionLevel.l3 => kb.ContextDepth.deep,
      SuggestionLevel.l2 => kb.ContextDepth.standard,
      SuggestionLevel.l1 => kb.ContextDepth.minimal,
    };

    // models/suggestion.dart 的 SuggestionLevel → knowledge_base.dart 的 SuggestionLevel
    final kbLevel = kb.SuggestionLevel.values[allowedLevel.index];

    // 从 KnowledgeBase 获取上下文
    // 请求最高层级上下文，实际深度由预算决定
    final ctx = await _kb.getDecisionContext(
      level: kbLevel,
      userDepth: depth,
    );

    final sb = StringBuffer();
    sb.writeln('【当前上下文】');
    sb.writeln(ctx.toPromptFragment());

    // 预算信息
    final remaining = await _budget.getRemaining();
    final budgetInfo = await _budget.getTierLabel();
    sb.writeln('预算档位：$budgetInfo（剩余 $remaining tok）');

    PetLogger().trace('SuggestionEngine',
        'buildDecisionContext: depth=$depth budget=$budgetInfo');
    return sb.toString().trim();
  }

  /// 判断当前是否应该生成建议
  Future<bool> shouldSuggest(SuggestionLevel level) async {
    final allowed = await _budget.getAllowedLevel();
    if (level.index > allowed.index) return false;
    return _budget.canAfford(level.estimatedTokens);
  }

  /// 获取当前预算允许的最高层级
  Future<SuggestionLevel> getAllowedLevel() => _budget.getAllowedLevel();

  void dispose() {
    // 当前无资源需释放，保留扩展点
  }
}
