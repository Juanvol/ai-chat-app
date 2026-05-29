// Flutter 3.24 / Dart 3.5
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/pet/pet_controller.dart';
import '../../lib/pet/pet_state.dart';

void main() {
  group('PetController 初始化', () {
    test('初始 status 为 idle', () {
      final c = PetController();
      expect(c.state.status, PetStatus.idle);
    });

    test('初始 hunger/mood/energy 均为 100', () {
      final c = PetController();
      expect(c.state.hunger, 100);
      expect(c.state.mood, 100);
      expect(c.state.energy, 100);
    });

    test('初始 affection 为 0', () {
      final c = PetController();
      expect(c.state.affection, 0);
    });

    test('初始 totalInteractions 为 0', () {
      final c = PetController();
      expect(c.state.totalInteractions, 0);
    });

    test('是 ChangeNotifier', () {
      final c = PetController();
      expect(c, isA<ChangeNotifier>());
    });
  });

  group('PetController 状态衰减', () {
    test('start() 启动后每分钟衰减', () async {
      final c = PetController(decayInterval: const Duration(milliseconds: 100));
      c.start();
      await Future.delayed(const Duration(milliseconds: 350));
      expect(c.state.hunger, lessThan(100));
      expect(c.state.mood, lessThan(100));
      expect(c.state.energy, lessThan(100));
      c.dispose();
    });

    test('衰减不低于 0', () async {
      final c = PetController(
        initialState: PetState(hunger: 1, mood: 1, energy: 1),
        decayInterval: const Duration(milliseconds: 50),
      );
      c.start();
      await Future.delayed(const Duration(milliseconds: 300));
      expect(c.state.hunger, 0);
      expect(c.state.mood, 0);
      expect(c.state.energy, 0);
      c.dispose();
    });

    test('stop() 后停止衰减', () async {
      final c = PetController(decayInterval: const Duration(milliseconds: 100));
      c.start();
      await Future.delayed(const Duration(milliseconds: 150));
      c.stop();
      final before = c.state.hunger;
      await Future.delayed(const Duration(milliseconds: 300));
      expect(c.state.hunger, before);
      c.dispose();
    });

    test('状态变化时 notifyListeners', () async {
      final c = PetController(decayInterval: const Duration(milliseconds: 100));
      int notifyCount = 0;
      c.addListener(() => notifyCount++);
      c.start();
      await Future.delayed(const Duration(milliseconds: 250));
      expect(notifyCount, greaterThan(0));
      c.dispose();
    });
  });

  group('PetController 自动状态切换', () {
    test('hunger < 30 自动切换到 hungry', () async {
      final c = PetController(
        initialState: PetState(hunger: 31),
        decayInterval: const Duration(milliseconds: 50),
      );
      c.start();
      await Future.delayed(const Duration(milliseconds: 200));
      expect(c.state.status, PetStatus.hungry);
      c.dispose();
    });

    test('hunger < 30 但 status 非 idle 时不切换', () async {
      final c = PetController(
        initialState: PetState(hunger: 25, status: PetStatus.eating),
        decayInterval: const Duration(milliseconds: 50),
      );
      c.start();
      await Future.delayed(const Duration(milliseconds: 200));
      expect(c.state.status, PetStatus.eating);
      c.dispose();
    });

    test('energy < 20 自动切换到 sleepy', () async {
      final c = PetController(
        initialState: PetState(energy: 21),
        decayInterval: const Duration(milliseconds: 50),
      );
      c.start();
      await Future.delayed(const Duration(milliseconds: 200));
      expect(c.state.status, PetStatus.sleepy);
      c.dispose();
    });

    test('hunger 和 energy 同时触发 → hunger 优先', () async {
      final c = PetController(
        initialState: PetState(hunger: 29, energy: 19),
        decayInterval: const Duration(milliseconds: 50),
      );
      c.start();
      await Future.delayed(const Duration(milliseconds: 200));
      expect(c.state.status, PetStatus.hungry);
      c.dispose();
    });
  });

  group('PetController 用户交互', () {
    test('feed() → hunger=100, status=eating', () {
      final c = PetController(initialState: PetState(hunger: 20));
      c.feed();
      expect(c.state.hunger, 100);
      expect(c.state.status, PetStatus.eating);
      c.dispose();
    });

    test('feed() → affection +10', () {
      final c = PetController(initialState: PetState(affection: 50));
      c.feed();
      expect(c.state.affection, 60);
      c.dispose();
    });

    test('feed() → totalInteractions +1', () {
      final c = PetController();
      c.feed();
      expect(c.state.totalInteractions, 1);
      c.dispose();
    });

    test('play() → mood=100, status=happy', () {
      final c = PetController(initialState: PetState(mood: 30));
      c.play();
      expect(c.state.mood, 100);
      expect(c.state.status, PetStatus.happy);
      c.dispose();
    });

    test('play() → affection +20', () {
      final c = PetController(initialState: PetState(affection: 50));
      c.play();
      expect(c.state.affection, 70);
      c.dispose();
    });

    test('chat() → status=talking', () {
      final c = PetController();
      c.chat();
      expect(c.state.status, PetStatus.talking);
      c.dispose();
    });

    test('chat() → affection +5', () {
      final c = PetController(initialState: PetState(affection: 50));
      c.chat();
      expect(c.state.affection, 55);
      c.dispose();
    });

    test('sleep() → status=sleeping', () {
      final c = PetController();
      c.sleep();
      expect(c.state.status, PetStatus.sleeping);
      c.dispose();
    });

    test('stopChatting() → 回到 idle', () {
      final c = PetController(initialState: PetState(status: PetStatus.talking));
      c.stopChatting();
      expect(c.state.status, PetStatus.idle);
      c.dispose();
    });

    test('affection 只增不减', () {
      final c = PetController(initialState: PetState(affection: 100));
      c.start();
      c.stop();
      expect(c.state.affection, 100);
      c.dispose();
    });
  });

  group('PetController 状态恢复', () {
    test('fromState 恢复正确的状态', () {
      final saved = PetState(hunger: 50, mood: 60, energy: 70, affection: 200, status: PetStatus.sleeping);
      final c = PetController.fromState(saved);
      expect(c.state.hunger, 50);
      expect(c.state.mood, 60);
      expect(c.state.energy, 70);
      expect(c.state.affection, 200);
      expect(c.state.status, PetStatus.sleeping);
      c.dispose();
    });
  });

  group('PetController dispose', () {
    test('dispose 后是安全的', () {
      final c = PetController();
      c.dispose();
    });
  });
}
