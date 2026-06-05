// Flutter 3.24 / Dart 3.5
import '../pet_token_service.dart';
import 'models/suggestion.dart';

/// 预算门控：根据剩余 Token 决定允许的建议层级
///
/// 通过闭包注入解耦测试，无需抽象接口。
/// 生产：`BudgetGate(getRemaining: PetTokenService.instance.getBudgetRemaining)`
/// 测试：`BudgetGate.test(remaining: 30000)`
class BudgetGate {
  static const _budgetFull = 20000;
  static const _budgetBalanced = 5000;
  static const _budgetVisionThreshold = 10000;
  static const _budgetSilent = 1000;
  final Future<int> Function() _getRemaining;

  /// 生产构造 — 注入任意异步查询函数
  BudgetGate({Future<int> Function()? getRemaining})
      : _getRemaining = getRemaining ?? PetTokenService.instance.getBudgetRemaining;

  /// 测试构造 — 固定返回值
  BudgetGate.test({required int remaining})
      : _getRemaining = (() async => remaining);

  /// 获取当前预算允许的最高建议层级
  Future<SuggestionLevel> getAllowedLevel() async {
    final remaining = await _getRemaining();
    if (remaining > _budgetFull) return SuggestionLevel.l4;
    if (remaining >= _budgetBalanced) return SuggestionLevel.l2;
    return SuggestionLevel.l1;
  }

  /// 是否能承担预估 token 消耗
  Future<bool> canAfford(int estimatedTokens) async {
    final remaining = await _getRemaining();
    return remaining >= estimatedTokens;
  }

  /// 是否允许视觉分析（预算 > 10k 才开）
  Future<bool> isVisionAllowed() async {
    final remaining = await _getRemaining();
    return remaining > _budgetVisionThreshold;
  }

  /// 预算档位 label（供 UI 显示）
  Future<String> getTierLabel() async {
    final remaining = await _getRemaining();
    if (remaining > _budgetFull) return '全力';
    if (remaining >= _budgetBalanced) return '均衡';
    if (remaining > _budgetSilent) return '省电';
    return '静默';
  }

  /// 当前剩余 Token
  Future<int> getRemaining() => _getRemaining();
}
