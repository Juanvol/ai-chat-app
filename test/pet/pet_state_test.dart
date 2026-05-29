// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import '../../lib/pet/pet_state.dart';

void main() {
  group('PetStatus', () {
    test('枚举值数量为 7', () {
      expect(PetStatus.values.length, 7);
    });

    test('name 属性与枚举小写一致', () {
      expect(PetStatus.idle.name, 'idle');
      expect(PetStatus.hungry.name, 'hungry');
      expect(PetStatus.eating.name, 'eating');
      expect(PetStatus.happy.name, 'happy');
      expect(PetStatus.sleepy.name, 'sleepy');
      expect(PetStatus.sleeping.name, 'sleeping');
      expect(PetStatus.talking.name, 'talking');
    });
  });

  group('PetState', () {
    test('默认构造函数产生正确的初始值', () {
      final state = PetState();
      expect(state.hunger, 100);
      expect(state.mood, 100);
      expect(state.energy, 100);
      expect(state.affection, 0);
      expect(state.status, PetStatus.idle);
      expect(state.totalInteractions, 0);
    });

    test('toJson 和 fromJson 往返一致', () {
      final original = PetState();
      final json = original.toJson();
      final restored = PetState.fromJson(json);
      expect(restored.hunger, original.hunger);
      expect(restored.mood, original.mood);
      expect(restored.energy, original.energy);
      expect(restored.affection, original.affection);
      expect(restored.status, original.status);
      expect(restored.totalInteractions, original.totalInteractions);
    });

    test('fromJson 恢复自定义值', () {
      final json = {
        'hunger': 50,
        'mood': 80,
        'energy': 30,
        'affection': 100,
        'status': 'hungry',
        'lastFed': '2026-05-30T10:00:00.000',
        'totalInteractions': 5,
      };
      final state = PetState.fromJson(json);
      expect(state.hunger, 50);
      expect(state.mood, 80.0);
      expect(state.energy, 30);
      expect(state.affection, 100);
      expect(state.status, PetStatus.hungry);
      expect(state.totalInteractions, 5);
    });

    test('copyWith 部分更新不丢失其他字段', () {
      final original = PetState(hunger: 50, mood: 80);
      final updated = original.copyWith(hunger: 100);
      expect(updated.hunger, 100);
      expect(updated.mood, 80);
      expect(updated.energy, original.energy);
      expect(updated.status, original.status);
    });

    test('copyWith 可同时更新多个字段', () {
      final original = PetState();
      final updated = original.copyWith(
        hunger: 0,
        status: PetStatus.hungry,
        affection: 10,
      );
      expect(updated.hunger, 0);
      expect(updated.status, PetStatus.hungry);
      expect(updated.affection, 10);
    });

    test('hunger 应 clamp 到 0-100', () {
      final low = PetState().copyWith(hunger: -5);
      final high = PetState().copyWith(hunger: 150);
      expect(low.hunger, 0);
      expect(high.hunger, 100);
    });

    test('mood 应 clamp 到 0-100', () {
      final low = PetState().copyWith(mood: -10);
      final high = PetState().copyWith(mood: 200);
      expect(low.mood, 0);
      expect(high.mood, 100);
    });

    test('energy 应 clamp 到 0-100', () {
      final low = PetState().copyWith(energy: -1);
      final high = PetState().copyWith(energy: 999);
      expect(low.energy, 0);
      expect(high.energy, 100);
    });

    test('affection 不应降到 0 以下', () {
      final state = PetState().copyWith(affection: -10);
      expect(state.affection, 0);
    });

    test('lastFed 默认值在构造时间附近', () {
      final before = DateTime.now();
      final state = PetState();
      final after = DateTime.now();
      expect(state.lastFed.isAfter(before) || state.lastFed == before, true);
      expect(state.lastFed.isBefore(after) || state.lastFed == after, true);
    });

    test('totalInteractions 不应降到 0 以下', () {
      final state = PetState().copyWith(totalInteractions: -1);
      expect(state.totalInteractions, 0);
    });

    test('affection 上界 clamp 到 999999', () {
      final state = PetState().copyWith(affection: 9999999);
      expect(state.affection, 999999);
    });

    test('totalInteractions 上界 clamp 到 999999', () {
      final state = PetState().copyWith(totalInteractions: 9999999);
      expect(state.totalInteractions, 999999);
    });
  });

  group('PetState fromJson 容错', () {
    test('未知 status 回退到 idle', () {
      final state = PetState.fromJson({'status': 'unknown_status'});
      expect(state.status, PetStatus.idle);
    });

    test('缺失字段使用默认值', () {
      final state = PetState.fromJson(<String, dynamic>{});
      expect(state.hunger, 100);
      expect(state.mood, 100);
      expect(state.energy, 100);
      expect(state.affection, 0);
      expect(state.status, PetStatus.idle);
      expect(state.totalInteractions, 0);
    });

    test('lastFed 为 null 时回退到当前时间', () {
      final before = DateTime.now();
      final state = PetState.fromJson({'lastFed': null});
      final after = DateTime.now();
      expect(state.lastFed.isAfter(before) || state.lastFed == before, true);
      expect(state.lastFed.isBefore(after) || state.lastFed == after, true);
    });

    test('lastFed 非法格式回退到当前时间', () {
      final state = PetState.fromJson({'lastFed': 'not-a-date'});
      final now = DateTime.now();
      expect(state.lastFed.difference(now).inSeconds.abs(), lessThan(5));
    });

    test('字段为 null 与缺失行为一致', () {
      final state = PetState.fromJson({'hunger': null, 'mood': null});
      expect(state.hunger, 100);
      expect(state.mood, 100);
    });
  });
}
