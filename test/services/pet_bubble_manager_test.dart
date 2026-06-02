// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/services/pet_bubble_manager.dart';
import 'package:deepseek_chat/services/pet_brain.dart';

void main() {
  group('PetBubbleManager', () {
    late PetBubbleManager mgr;

    setUp(() => mgr = PetBubbleManager());

    test('气泡池非空', () {
      expect(mgr.totalCount, greaterThan(80));
    });

    test('早晨返回问候类气泡（不含深夜内容）', () {
      final b = mgr.pick(category: 'greeting', period: DayPeriod.morning);
      expect(b, isNotNull);
      // 早晨池子不应包含晚安/深夜类内容
      expect(b!.contains('晚安'), isFalse);
      expect(b.contains('深夜'), isFalse);
    });

    test('深夜不返回早安', () {
      // 深夜的问候应为晚安类
      final b = mgr.pick(category: 'greeting', period: DayPeriod.night);
      expect(b, isNotNull);
      // 深夜不包含"早安"（深夜池子是 _night）
      expect(b!.contains('早安'), isFalse);
    });

    test('冷却期内返回 null', () {
      final b1 = mgr.pick(category: 'affection', period: DayPeriod.afternoon);
      expect(b1, isNotNull);
      // 立即再取同分类 → 应为 null（冷却）
      final b2 = mgr.pick(category: 'affection', period: DayPeriod.afternoon);
      expect(b2, isNull);
    });

    test('resetCooldown 后可以再取', () {
      mgr.pick(category: 'affection', period: DayPeriod.afternoon);
      mgr.resetCooldown('affection');
      final b = mgr.pick(category: 'affection', period: DayPeriod.afternoon);
      expect(b, isNotNull);
    });

    test('不同分类不共享冷却', () {
      mgr.pick(category: 'greeting', period: DayPeriod.morning);
      final b = mgr.pick(category: 'affection', period: DayPeriod.morning);
      expect(b, isNotNull);
    });
  });
}
