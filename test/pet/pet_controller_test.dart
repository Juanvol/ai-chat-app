// Flutter 3.24 / Dart 3.5
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/pet/pet_controller.dart';
import 'package:deepseek_chat/models/pet_state.dart';

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

  // ── 回归测试 ──

  group('PetController regression', () {
    test('restoreFromState 触发 onStateChanged (regression #5)', () {
      // bug: restoreFromState 调了 notifyListeners 而非 _notify，跳过 onStateChanged
      PetState? saved;
      final c = PetController(onStateChanged: (s) => saved = s);
      c.restoreFromState(PetState(hunger: 42));
      expect(saved, isNotNull);
      expect(saved!.hunger, 42);
      c.dispose();
    });

    test('feed 后 transition 到 idle 时触发 _checkAutoTransition (regression #4)', () async {
      // bug: _scheduleTransition 回调未调 _checkAutoTransition
      // feed 将 hunger 重置到 100，所以用 energy < 20 来验证 auto-transition
      final c = PetController(
        initialState: PetState(energy: 15), // energy<20，feed 不改变 energy
        decayInterval: const Duration(hours: 1),
      );
      c.feed(); // hunger=100, status=eating, 4秒后切 idle
      expect(c.state.status, PetStatus.eating);
      await Future<void>.delayed(const Duration(seconds: 5));
      // 修复前：idle（_checkAutoTransition 未调）
      // 修复后：sleepy（energy < 20 触发 _checkAutoTransition）
      expect(c.state.status, PetStatus.sleepy);
      c.dispose();
    });

    test('stopChatting 后触发 _checkAutoTransition (regression #4b)', () {
      final c = PetController(
        initialState: PetState(hunger: 20, status: PetStatus.talking),
        decayInterval: const Duration(hours: 1),
      );
      c.stopChatting();
      // 修复前：status 是 idle（_checkAutoTransition 未调）
      // 修复后：status 是 hungry
      expect(c.state.status, PetStatus.hungry);
      c.dispose();
    });

    test('restoreFromState 恢复 eating 状态 → 立即切 idle (regression #6)', () {
      // bug: 恢复 eating/happy 过渡状态时没有调度 transition，导致永久卡住
      final c = PetController(
        decayInterval: const Duration(hours: 1),
      );
      c.restoreFromState(PetState(hunger: 100, status: PetStatus.eating));
      // 修复后：eating → idle
      expect(c.state.status, PetStatus.idle);
      c.dispose();
    });

    test('restoreFromState 恢复 happy → 立即切 idle (regression #6b)', () {
      final c = PetController(
        decayInterval: const Duration(hours: 1),
      );
      c.restoreFromState(PetState(mood: 100, status: PetStatus.happy));
      expect(c.state.status, PetStatus.idle);
      c.dispose();
    });

    test('restoreFromState 恢复 idle 且 hunger<30 → 立即 hungry (regression #7)', () {
      // bug: restoreFromState 缺少 _checkAutoTransition，恢复后不检查阈值
      final c = PetController(
        decayInterval: const Duration(hours: 1),
      );
      c.restoreFromState(PetState(hunger: 20, status: PetStatus.idle));
      // 修复后：hunger<30 → hungry
      expect(c.state.status, PetStatus.hungry);
      c.dispose();
    });

    test('restoreFromState 恢复 eating + 低 energy → idle → sleepy (regression #6+#7)', () {
      // eating→idle 后 _checkAutoTransition 检测到 energy<20 → sleepy
      final c = PetController(
        decayInterval: const Duration(hours: 1),
      );
      c.restoreFromState(PetState(hunger: 100, energy: 15, status: PetStatus.eating));
      // eating → idle → sleepy
      expect(c.state.status, PetStatus.sleepy);
      c.dispose();
    });
  });
}
