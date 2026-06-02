// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/pet_logger.dart';
import 'pet_state.dart';

class PetController extends ChangeNotifier {
  PetState _state;
  final Duration decayInterval;
  Timer? _decayTimer;
  Timer? _transitionTimer;
  DateTime _lastInteractionAt;
  void Function(PetState state)? onStateChanged;

  PetController({
    PetState? initialState,
    this.decayInterval = const Duration(minutes: 1),
    this.onStateChanged,
  }) : _state = initialState ?? PetState(),
       _lastInteractionAt = initialState?.lastFed ?? DateTime.now();

  PetController.fromState(PetState state, {Duration? decayInterval, this.onStateChanged})
      : _state = state,
        decayInterval = decayInterval ?? const Duration(minutes: 1),
        _lastInteractionAt = state.lastFed;

  PetState get state => _state;

  // ── 深度休眠 ──

  bool get isDeepSleeping =>
      DateTime.now().difference(_lastInteractionAt).inHours >= 6 &&
      _state.status != PetStatus.eating &&
      _state.status != PetStatus.talking;

  void wakeUp() {
    PetLogger().info('Controller', 'wakeUp from ' + _state.status.name);
    _lastInteractionAt = DateTime.now();
    if (_state.status == PetStatus.sleeping) {
      _state = _state.copyWith(status: PetStatus.idle);
      _notify();
    }
  }

  // ── 生命周期 ──

  void start() {
    PetLogger().info('Controller', 'start');
    _decayTimer?.cancel();
    _decayTimer = Timer.periodic(decayInterval, (_) => _decay());
  }

  void stop() {
    PetLogger().info('Controller', 'stop');
    _decayTimer?.cancel();
    _decayTimer = null;
    _transitionTimer?.cancel();
    _transitionTimer = null;
  }

  static const _noDecayStatuses = {
    PetStatus.eating,
    PetStatus.happy,
    PetStatus.sleeping,
    PetStatus.talking,
  };

  void _decay() {
    if (isDeepSleeping) { PetLogger().trace('Controller', 'decay skipped: deep sleeping'); return; }
    // 用户主动触发的交互状态不衰减，警告状态（hungry/sleepy）继续衰减
    if (_noDecayStatuses.contains(_state.status)) { PetLogger().trace('Controller', 'decay skipped: status=' + _state.status.name); return; }
    _state = _state.copyWith(
      hunger: (_state.hunger - 1).clamp(0, 100),
      mood: (_state.mood - 0.5).clamp(0, 100),
      energy: (_state.energy - 1).clamp(0, 100),
    );
    _checkAutoTransition();
    _notify();
  }

  void _checkAutoTransition() {
    if (_state.status != PetStatus.idle) return;
    if (_state.hunger < 30) {
      _state = _state.copyWith(status: PetStatus.hungry);
    } else if (_state.energy < 20) {
      _state = _state.copyWith(status: PetStatus.sleepy);
    }
  }

  // ── 用户交互 ──

  void feed() {
    _cancelTransition();
    _markInteraction();
    _state = _state.copyWith(
      hunger: 100,
      status: PetStatus.eating,
      affection: _state.affection + 10,
      totalInteractions: _state.totalInteractions + 1,
      lastFed: DateTime.now(),
    );
    PetLogger().trace('Controller', 'feed -> eating, affection=' + _state.affection.toString());
    _notify();
    _scheduleTransition(PetStatus.idle, const Duration(seconds: 4));
  }

  void play() {
    _cancelTransition();
    _markInteraction();
    _state = _state.copyWith(
      mood: 100,
      status: PetStatus.happy,
      affection: _state.affection + 20,
      totalInteractions: _state.totalInteractions + 1,
      lastFed: DateTime.now(),
    );
    PetLogger().trace('Controller', 'play -> happy, affection=' + _state.affection.toString());
    _notify();
    _scheduleTransition(PetStatus.idle, const Duration(seconds: 4));
  }

  void pet() {
    _cancelTransition();
    _markInteraction();
    _state = _state.copyWith(
      mood: (_state.mood + 10).clamp(0, 100),
      status: PetStatus.happy,
      affection: _state.affection + 5,
      totalInteractions: _state.totalInteractions + 1,
    );
    PetLogger().trace('Controller', 'pet -> happy, mood=' + _state.mood.toString());
    _notify();
    _scheduleTransition(PetStatus.idle, const Duration(seconds: 3));
  }

  void chat() {
    _cancelTransition();
    _markInteraction();
    _state = _state.copyWith(
      status: PetStatus.talking,
      affection: _state.affection + 5,
      totalInteractions: _state.totalInteractions + 1,
      lastFed: DateTime.now(),
    );
    PetLogger().trace('Controller', 'chat -> talking, affection=' + _state.affection.toString());
    _notify();
  }

  void sleep() {
    _cancelTransition();
    _markInteraction();
    _state = _state.copyWith(status: PetStatus.sleeping, lastFed: DateTime.now());
    PetLogger().trace('Controller', 'sleep -> sleeping');
    _notify();
  }

  void stopChatting() {
    if (_state.status == PetStatus.talking) {
      PetLogger().trace('Controller', 'stopChatting -> idle');
      _state = _state.copyWith(status: PetStatus.idle);
      _checkAutoTransition();
      _notify();
    }
  }

  // ── 状态恢复 ──

  void restoreFromState(PetState saved) {
    PetLogger().info('Controller', 'restoreFromState status=' + saved.status.name + ' h=' + saved.hunger.toString() + ' e=' + saved.energy.toString());
    _state = saved;
    _lastInteractionAt = saved.lastFed;
    // Bug #6: 恢复 eating/happy 过渡状态时卡住，立即切回 idle
    if (_state.status == PetStatus.eating || _state.status == PetStatus.happy) {
      _state = _state.copyWith(status: PetStatus.idle);
    }
    // Bug #7: 恢复后立即检查是否需要触发 hungry/sleepy
    _checkAutoTransition();
    _notify();
  }

  // ── 内部方法 ──

  void _markInteraction() {
    _lastInteractionAt = DateTime.now();
  }

  void _notify() {
    notifyListeners();
    onStateChanged?.call(_state);
  }

  void _cancelTransition() {
    _transitionTimer?.cancel();
    _transitionTimer = null;
  }

  void _scheduleTransition(PetStatus target, Duration delay) {
    _transitionTimer?.cancel();
    _transitionTimer = Timer(delay, () {
      if (_state.status != PetStatus.talking && _state.status != PetStatus.sleeping) {
        _state = _state.copyWith(status: target);
        _checkAutoTransition();
        _notify();
      }
    });
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
