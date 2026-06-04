// Flutter 3.24 / Dart 3.5
import 'package:flutter/foundation.dart';
import '../../models/token_usage.dart';
import '../../models/model_config.dart';
import 'storage_service.dart';

class TokenStatsService extends ChangeNotifier {
  final StorageService _storage;

  TokenStatsService({required StorageService storage}) : _storage = storage;

  List<TokenUsage> get usages => _storage.getUsages();

  int get totalPromptTokens => usages.fold(0, (s, u) => s + u.promptTokens);
  int get totalCompletionTokens => usages.fold(0, (s, u) => s + u.completionTokens);
  int get totalTokens => totalPromptTokens + totalCompletionTokens;

  Map<String, List<TokenUsage>> get usageByModel {
    final map = <String, List<TokenUsage>>{};
    for (final u in usages) {
      map.putIfAbsent(u.modelId, () => []).add(u);
    }
    return Map.unmodifiable(map);
  }

  /// 最近 [days] 天的每日统计
  List<({DateTime date, int tokens, int count})> dailyStats(int days) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    final daily = <DateTime, ({int tokens, int count})>{};
    for (final u in usages) {
      final d = DateTime(u.createdAt.year, u.createdAt.month, u.createdAt.day);
      if (d.isBefore(cutoff)) continue;
      final cur = daily[d] ?? (tokens: 0, count: 0);
      daily[d] = (tokens: cur.tokens + u.totalTokens, count: cur.count + 1);
    }
    final result = <({DateTime date, int tokens, int count})>[];
    for (var d = cutoff; !d.isAfter(now); d = d.add(const Duration(days: 1))) {
      final entry = daily[DateTime(d.year, d.month, d.day)];
      result.add((date: d, tokens: entry?.tokens ?? 0, count: entry?.count ?? 0));
    }
    return result;
  }

  /// 某模型总费用（人民币）
  double costForModel(String modelId) {
    final model = ModelConfig.builtIn.where((m) => m.id == modelId).firstOrNull;
    if (model == null) return 0;
    double cost = 0;
    for (final u in usages) {
      if (u.modelId != modelId) continue;
      cost += (u.promptTokens / 1000000) * model.inputPricePerM;
      cost += (u.completionTokens / 1000000) * model.outputPricePerM;
    }
    return cost;
  }

  /// 全部费用（人民币）
  double get totalCostCNY {
    double total = 0;
    for (final model in ModelConfig.builtIn) {
      total += costForModel(model.id);
    }
    return total;
  }

  Map<String, double> get costByModel {
    final map = <String, double>{};
    for (final entry in usageByModel.entries) {
      map[entry.key] = costForModel(entry.key);
    }
    return Map.unmodifiable(map);
  }

  void refresh() {
    notifyListeners();
  }
}
