// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/services/pet_brain.dart';
import 'package:deepseek_chat/services/pet_agent_core.dart';

void main() {
  group('BehaviorWeights', () {
    test('基础权重总和为 115', () {
      final w = BehaviorWeights();
      expect(w.total, 115);
    });

    test('深夜调整：睡眠权重×3，走动权重×0.3', () {
      final w = BehaviorWeights();
      w.applyContext(hour: 2, hunger: 80, energy: 80, mood: 0.5, al: AttentionLevel.L3);
      expect(w.sleep, greaterThan(4)); // 原本 2，×3 = 6
      expect(w.wander, lessThan(10));  // 原本 15，×0.3 = 4.5
    });

    test('饥饿时 hungryBubble 权重提升', () {
      final w = BehaviorWeights();
      final before = w.hungryBubble;
      w.applyContext(hour: 14, hunger: 20, energy: 80, mood: 0.5, al: AttentionLevel.L3);
      expect(w.hungryBubble, greaterThan(before));
    });

    test('疲劳时 sit 权重×2.5', () {
      final w = BehaviorWeights();
      w.applyContext(hour: 14, hunger: 80, energy: 10, mood: 0.5, al: AttentionLevel.L3);
      expect(w.sitDown, greaterThan(20)); // 原本 10，×2.5 = 25
    });

    test('L0 休眠全部归零除了睡眠', () {
      final w = BehaviorWeights();
      w.applyContext(hour: 14, hunger: 80, energy: 80, mood: 0.5, al: AttentionLevel.L0);
      expect(w.idleBreath, 0);
      expect(w.wander, 0);
      expect(w.sleep, greaterThan(0));
    });
  });

  group('IdleTier', () {
    test('0-20s 为 Tier1', () {
      expect(IdleTierExt.fromIdleSeconds(0), IdleTier.tier1);
      expect(IdleTierExt.fromIdleSeconds(19), IdleTier.tier1);
    });

    test('20-90s 为 Tier2', () {
      expect(IdleTierExt.fromIdleSeconds(20), IdleTier.tier2);
      expect(IdleTierExt.fromIdleSeconds(89), IdleTier.tier2);
    });

    test('90s+ 为 Tier3', () {
      expect(IdleTierExt.fromIdleSeconds(90), IdleTier.tier3);
      expect(IdleTierExt.fromIdleSeconds(999), IdleTier.tier3);
    });
  });

  group('DayPeriod', () {
    test('6-9 为早晨', () {
      expect(DayPeriodExt.fromHour(6), DayPeriod.morning);
      expect(DayPeriodExt.fromHour(8), DayPeriod.morning);
    });
    test('9-12 为上午', () => expect(DayPeriodExt.fromHour(10), DayPeriod.morningWork));
    test('12-18 为下午', () => expect(DayPeriodExt.fromHour(15), DayPeriod.afternoon));
    test('18-22 为傍晚', () => expect(DayPeriodExt.fromHour(20), DayPeriod.evening));
    test('22-6 为深夜', () {
      expect(DayPeriodExt.fromHour(23), DayPeriod.night);
      expect(DayPeriodExt.fromHour(3), DayPeriod.night);
    });
  });

  group('PokeTracker', () {
    test('1次戳触发 bounce', () {
      final t = PokeTracker();
      final r = t.recordPoke();
      expect(r, PokeReaction.bounce);
    });

    test('3次戳(2s内)触发 annoyed', () {
      final t = PokeTracker();
      t.recordPoke(); // 1 → bounce
      t.recordPoke(); // 2 → bounce
      final r = t.recordPoke(); // 3 → annoyed
      expect(r, PokeReaction.annoyed);
    });

    test('冷却后戳计数重置（dt 超过 2s 窗口）', () {
      final t = PokeTracker();
      t.recordPoke();
      t.recordPoke();
      t.recordPoke(); // 3 pokes → annoyed
      // 模拟 3 秒后，计数窗口过期
      final r = t.recordPoke(dt: 3.0); // 新的第1次戳
      expect(r, PokeReaction.bounce);
    });

    test('10次戳触发 playDead', () {
      final t = PokeTracker();
      PokeReaction? last;
      for (int i = 0; i < 10; i++) {
        last = t.recordPoke();
      }
      expect(last, PokeReaction.playDead);
    });
  });
}
