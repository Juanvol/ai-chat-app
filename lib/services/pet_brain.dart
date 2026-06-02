// Flutter 3.24 / Dart 3.5
import 'dart:math';
import 'pet_agent_core.dart';

enum DayPeriod { morning, morningWork, afternoon, evening, night }

enum IdleTier { tier1, tier2, tier3 }

enum PokeReaction { none, bounce, annoyed, playDead }

extension DayPeriodExt on DayPeriod {
  static DayPeriod fromHour(int hour) => switch (hour) {
    >= 6 && < 9 => DayPeriod.morning,
    >= 9 && < 12 => DayPeriod.morningWork,
    >= 12 && < 18 => DayPeriod.afternoon,
    >= 18 && < 22 => DayPeriod.evening,
    _ => DayPeriod.night,
  };
}

extension IdleTierExt on IdleTier {
  static IdleTier fromIdleSeconds(int seconds) => switch (seconds) {
    < 20 => IdleTier.tier1,
    < 90 => IdleTier.tier2,
    _ => IdleTier.tier3,
  };
}

class BehaviorWeights {
  int idleBreath = 50;
  int lookAround = 20;
  int wander = 15;
  int sitDown = 10;
  int rareAction = 5;
  int hungryBubble = 8;
  int sleep = 2;
  int speakBubble = 5;

  int get total => idleBreath + lookAround + wander + sitDown +
      rareAction + hungryBubble + sleep + speakBubble;

  final _rng = Random();

  void applyContext({
    required int hour,
    required int hunger,
    required int energy,
    required double mood,
    required AttentionLevel al,
  }) {
    // 重置
    idleBreath = 50; lookAround = 20; wander = 15; sitDown = 10;
    rareAction = 5; hungryBubble = 8; sleep = 2; speakBubble = 5;

    // 时段主题
    switch (DayPeriodExt.fromHour(hour)) {
      case DayPeriod.morning:
        lookAround = (lookAround * 2).round();
        rareAction = (rareAction * 2).round();
      case DayPeriod.morningWork:
        idleBreath = (idleBreath * 1.5).round();
        wander = (wander * 0.5).round();
      case DayPeriod.afternoon:
        wander = (wander * 1.5).round();
        rareAction = (rareAction * 1.5).round();
      case DayPeriod.evening:
        speakBubble = (speakBubble * 2).round();
        sitDown = (sitDown * 2).round();
      case DayPeriod.night:
        sleep = (sleep * 3).round();
        wander = (wander * 0.3).round();
        speakBubble = (speakBubble * 0.3).round();
    }

    // 身体状态
    if (hunger < 30) hungryBubble = (hungryBubble * 4).round();
    if (energy < 20) { sitDown = (sitDown * 2.5).round(); wander = (wander * 0.2).round(); }
    if (mood > 0.8) rareAction = (rareAction * 2).round();

    // 关注度
    switch (al) {
      case AttentionLevel.L3: break;
      case AttentionLevel.L2:
        wander = (wander * 0.7).round();
        speakBubble = (speakBubble * 0.5).round();
      case AttentionLevel.L1:
        wander = (wander * 0.5).round();
        speakBubble = (speakBubble * 0.3).round();
      case AttentionLevel.L0:
        idleBreath = 0; lookAround = 0; wander = 0; sitDown = 0;
        rareAction = 0; hungryBubble = 0; speakBubble = 0;
        sleep = 100;
    }
  }

  /// 加权随机选择，返回动作名称。
  String pickAction() {
    final total = this.total;
    if (total <= 0) return 'sleep';
    var roll = _rng.nextInt(total);
    for (final entry in [
      ('idleBreath', idleBreath), ('lookAround', lookAround),
      ('wander', wander), ('sitDown', sitDown),
      ('rareAction', rareAction), ('hungryBubble', hungryBubble),
      ('sleep', sleep), ('speakBubble', speakBubble),
    ]) {
      roll -= entry.$2;
      if (roll < 0) return entry.$1;
    }
    return 'idleBreath';
  }
}

class PokeTracker {
  int count = 0;
  double _pokeTimer = 0;
  static const _window = 2.0; // 2秒窗口

  /// 记录一次戳。dt 为距上次调用的秒数（用于测试模拟时间流逝）。
  /// 返回对应的戳宠反应等级。
  PokeReaction recordPoke({double dt = 0}) {
    _pokeTimer += dt;
    if (_pokeTimer > _window) count = 0;
    count++;
    _pokeTimer = 0;
    if (count >= 10) return PokeReaction.playDead;
    if (count >= 3) return PokeReaction.annoyed;
    if (count >= 1) return PokeReaction.bounce;
    return PokeReaction.none;
  }
}

class UserRhythm {
  final _interactions = <DateTime>[];
  static const _window = Duration(minutes: 5);
  int _freqPerMin = 0;

  void recordInteraction() {
    final now = DateTime.now();
    _interactions.add(now);
    _interactions.removeWhere((t) => now.difference(t) > _window);
    _freqPerMin = _interactions.length;
  }

  int get freqPerMin => _freqPerMin;

  AttentionLevel suggestLevel(AttentionLevel current) {
    if (_freqPerMin > 10) return AttentionLevel.L2;  // 用户忙 → 安静
    if (_freqPerMin < 3 && current == AttentionLevel.L2) return AttentionLevel.L3;
    return current;
  }
}

class DailyMood {
  final double moodSeed;
  final String emoji;
  final String label;

  DailyMood._(this.moodSeed, this.emoji, this.label);

  factory DailyMood.today() {
    final rng = Random(DateTime.now().year * 10000 +
        DateTime.now().month * 100 + DateTime.now().day);
    final seed = 0.5 + (rng.nextDouble() - 0.5) * 0.5; // 0.25-0.75
    if (seed > 0.75) return DailyMood._(seed, '😸', '今天心情超好');
    if (seed < 0.25) return DailyMood._(seed, '😼', '今天是糯糯的小脾气日');
    return DailyMood._(seed, '😊', '普通的一天');
  }
}
