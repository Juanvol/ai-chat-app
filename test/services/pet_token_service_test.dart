// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:deepseek_chat/services/pet/pet_token_service.dart';

void main() {
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('pet_token_test_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
  });

  group('PetTokenService', () {
    test('recordTokens 记录并累加', () async {
      final svc = PetTokenService.instance;
      await svc.recordTokens(decision: 100, chat: 200);
      final today = await svc.getTodayUsage();
      expect(today.decisionTokens, 100);
      expect(today.chatTokens, 200);
      expect(today.totalTokens, 300);

      await svc.recordTokens(decision: 50, vision: 30);
      final updated = await svc.getTodayUsage();
      expect(updated.decisionTokens, 150);
      expect(updated.visionTokens, 30);
      expect(updated.totalTokens, 380);
    });

    test('getWeekUsage 返回最近 7 天', () async {
      final svc = PetTokenService.instance;
      await svc.recordTokens(decision: 100);
      final week = await svc.getWeekUsage();
      expect(week.length, lessThanOrEqualTo(7));
      expect(week.any((d) => d.totalTokens > 0), true);
    });

    test('checkBudget 额度检查', () async {
      final svc = PetTokenService.instance;
      expect(await svc.checkBudget(), true);
      expect(await svc.getBudgetRemaining(), 50000);

      await svc.recordTokens(decision: 50001);
      expect(await svc.checkBudget(), false);
      expect(await svc.getBudgetRemaining(), -1);
    });

    test('不限制模式 checkBudget 永远 true', () async {
      final svc = PetTokenService.instance;
      await svc.setBudget(null);
      await svc.recordTokens(decision: 999999);
      expect(await svc.checkBudget(), true);
    });

    test('getBudgetUsageFraction 返回 0.0~1.0', () async {
      final svc = PetTokenService.instance;
      await svc.setBudget(100);
      await svc.recordTokens(decision: 30);
      final fraction = await svc.getBudgetUsageFraction();
      expect(fraction, closeTo(0.3, 0.01));
    });
  });
}
