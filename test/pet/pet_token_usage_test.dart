// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/models/pet_token_usage.dart';

void main() {
  group('PetTokenUsage', () {
    test('toJson/fromJson 往返', () {
      final usage = PetTokenUsage(
        date: DateTime(2026, 5, 30),
        decisionTokens: 1000,
        chatTokens: 5000,
        visionTokens: 2000,
        totalTokens: 8000,
      );
      final json = usage.toJson();
      final restored = PetTokenUsage.fromJson(json);
      expect(restored.date, DateTime(2026, 5, 30));
      expect(restored.decisionTokens, 1000);
      expect(restored.chatTokens, 5000);
      expect(restored.visionTokens, 2000);
      expect(restored.totalTokens, 8000);
    });

    test('默认值', () {
      final usage = PetTokenUsage();
      expect(usage.decisionTokens, 0);
      expect(usage.chatTokens, 0);
      expect(usage.visionTokens, 0);
      expect(usage.totalTokens, 0);
    });

    test('add 累加正确', () {
      final usage = PetTokenUsage();
      final updated = usage.add(decision: 100, chat: 200, vision: 50);
      expect(updated.decisionTokens, 100);
      expect(updated.chatTokens, 200);
      expect(updated.visionTokens, 50);
      expect(updated.totalTokens, 350);
    });

    test('dateKey 格式正确', () {
      final usage = PetTokenUsage(date: DateTime(2026, 5, 30));
      expect(usage.dateKey, '2026-05-30');
    });
  });
}
