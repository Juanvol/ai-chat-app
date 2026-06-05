// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/services/pet/suggestion/budget_gate.dart';
import 'package:deepseek_chat/services/pet/suggestion/models/suggestion.dart';

void main() {
  group('BudgetGate', () {
    test('剩余 > 20k → L4', () async {
      final gate = BudgetGate.test(remaining: 30000);
      expect(await gate.getAllowedLevel(), SuggestionLevel.l4);
    });

    test('剩余 5k-20k → L2', () async {
      final gate = BudgetGate.test(remaining: 10000);
      expect(await gate.getAllowedLevel(), SuggestionLevel.l2);
    });

    test('剩余 < 5k → L1', () async {
      final gate = BudgetGate.test(remaining: 3000);
      expect(await gate.getAllowedLevel(), SuggestionLevel.l1);
    });

    test('边界值：恰好 20000 → L2', () async {
      final gate = BudgetGate.test(remaining: 20000);
      expect(await gate.getAllowedLevel(), SuggestionLevel.l2);
    });

    test('边界值：恰好 5000 → L2', () async {
      final gate = BudgetGate.test(remaining: 5000);
      expect(await gate.getAllowedLevel(), SuggestionLevel.l2);
    });

    test('canAfford 足够', () async {
      final gate = BudgetGate.test(remaining: 5000);
      expect(await gate.canAfford(500), isTrue);
    });

    test('canAfford 不足', () async {
      final gate = BudgetGate.test(remaining: 200);
      expect(await gate.canAfford(500), isFalse);
    });

    test('canAfford 刚好相等', () async {
      final gate = BudgetGate.test(remaining: 500);
      expect(await gate.canAfford(500), isTrue);
    });

    test('canAfford 0 token', () async {
      final gate = BudgetGate.test(remaining: 100);
      expect(await gate.canAfford(0), isTrue);
    });

    test('isVisionAllowed > 10k', () async {
      final gate = BudgetGate.test(remaining: 15000);
      expect(await gate.isVisionAllowed(), isTrue);
    });

    test('isVisionAllowed < 10k', () async {
      final gate = BudgetGate.test(remaining: 5000);
      expect(await gate.isVisionAllowed(), isFalse);
    });

    test('isVisionAllowed 边界：恰好 10000', () async {
      final gate = BudgetGate.test(remaining: 10000);
      expect(await gate.isVisionAllowed(), isFalse);
    });

    test('getTierLabel 各档位', () async {
      expect(await BudgetGate.test(remaining: 30000).getTierLabel(), '全力');
      expect(await BudgetGate.test(remaining: 10000).getTierLabel(), '均衡');
      expect(await BudgetGate.test(remaining: 3000).getTierLabel(), '省电');
      expect(await BudgetGate.test(remaining: 500).getTierLabel(), '静默');
    });

    test('getTierLabel 边界值', () async {
      expect(await BudgetGate.test(remaining: 20000).getTierLabel(), '均衡');
      expect(await BudgetGate.test(remaining: 5000).getTierLabel(), '均衡');
      expect(await BudgetGate.test(remaining: 1000).getTierLabel(), '静默');
    });
  });
}
