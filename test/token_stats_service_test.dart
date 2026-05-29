// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/services/token_stats_service.dart';
import 'package:deepseek_chat/models/token_usage.dart';
import 'fake_storage_service.dart';

void main() {
  group('TokenStatsService', () {
    late FakeStorageService storage;
    late TokenStatsService service;

    setUp(() {
      storage = FakeStorageService();
      service = TokenStatsService(storage: storage);
    });

    void addUsage(String modelId, String providerId, int prompt, int completion) {
      storage.saveUsage(TokenUsage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        conversationId: 'c1',
        modelId: modelId,
        providerId: providerId,
        promptTokens: prompt,
        completionTokens: completion,
        createdAt: DateTime.now(),
      ));
    }

    test('空数据时各聚合值为 0', () {
      expect(service.usages, isEmpty);
      expect(service.totalPromptTokens, 0);
      expect(service.totalCompletionTokens, 0);
      expect(service.totalTokens, 0);
      expect(service.usageByModel, isEmpty);
      expect(service.totalCostCNY, 0);
    });

    test('totalPromptTokens / totalCompletionTokens / totalTokens 正确聚合', () {
      addUsage('ds-v4-pro', 'deepseek', 100, 200);
      addUsage('ds-v4-pro', 'deepseek', 50, 80);
      expect(service.totalPromptTokens, 150);
      expect(service.totalCompletionTokens, 280);
      expect(service.totalTokens, 430);
    });

    test('usageByModel 按 modelId 分组', () {
      addUsage('ds-v4-pro', 'deepseek', 100, 200);
      addUsage('gpt-4o', 'openai', 50, 100);
      expect(service.usageByModel.length, 2);
      expect(service.usageByModel['ds-v4-pro']!.length, 1);
      expect(service.usageByModel['gpt-4o']!.length, 1);
    });

    test('costForModel 根据定价计算费用（人民币）', () {
      // ds-v4-pro: input ¥2.02/MTok, output ¥6.05/MTok
      addUsage('ds-v4-pro', 'deepseek', 1000000, 1000000);
      final cost = service.costForModel('ds-v4-pro');
      expect(cost, closeTo(2.02 + 6.05, 0.001));
    });

    test('costForModel 不存在的 model 返回 0', () {
      expect(service.costForModel('nonexistent'), 0);
    });

    test('totalCostCNY 汇总所有模型费用', () {
      // ds-v4-pro: input ¥2.02/MTok
      addUsage('ds-v4-pro', 'deepseek', 1000000, 0);
      // glm4-plus: input ¥50/MTok
      addUsage('glm4-plus', 'zhipu', 1000000, 0);
      expect(service.totalCostCNY, closeTo(2.02 + 50, 0.01));
    });

    test('costByModel 返回各模型费用映射', () {
      addUsage('ds-v4-pro', 'deepseek', 1000000, 0);
      addUsage('gpt-4o', 'openai', 1000000, 0);
      final costs = service.costByModel;
      expect(costs.length, 2);
      expect(costs['ds-v4-pro'], closeTo(2.02, 0.001));
      expect(costs['gpt-4o'], closeTo(18.00, 0.001));
    });

    test('dailyStats 按天聚合并包含 0 值的日期', () {
      addUsage('ds-v4-pro', 'deepseek', 100, 200);
      final stats = service.dailyStats(7);
      expect(stats.length, 8);
      final today = stats.last;
      expect(today.tokens, 300);
      expect(today.count, 1);
      final yesterday = stats[stats.length - 2];
      expect(yesterday.tokens, 0);
      expect(yesterday.count, 0);
    });

    test('dailyStats 过滤超出范围的旧数据', () {
      final oldUsage = TokenUsage(
        id: 'old',
        conversationId: 'c1',
        modelId: 'ds-v4-pro',
        providerId: 'deepseek',
        promptTokens: 999,
        completionTokens: 999,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      );
      storage.saveUsage(oldUsage);
      final stats = service.dailyStats(7);
      for (final s in stats) {
        expect(s.tokens, 0);
      }
    });

    test('refresh 触发 notifyListeners', () {
      var called = false;
      service.addListener(() => called = true);
      service.refresh();
      expect(called, isTrue);
    });
  });
}
