// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'pet_state.dart';

class PetController extends ChangeNotifier {
  PetState _state;
  final Duration decayInterval;
  Timer? _decayTimer;

  PetController({
    PetState? initialState,
    this.decayInterval = const Duration(minutes: 1),
  }) : _state = initialState ?? PetState();

  PetController.fromState(PetState state, {Duration? decayInterval})
      : _state = state,
        decayInterval = decayInterval ?? const Duration(minutes: 1);

  PetState get state => _state;

  // ── 生命周期 ──

  void start() {
    _decayTimer?.cancel();
    _decayTimer = Timer.periodic(decayInterval, (_) => _decay());
  }

  void stop() {
    _decayTimer?.cancel();
    _decayTimer = null;
  }

  void _decay() {
    _state = _state.copyWith(
      hunger: (_state.hunger - 1).clamp(0, 100),
      mood: (_state.mood - 0.5).clamp(0, 100),
      energy: (_state.energy - 1).clamp(0, 100),
    );
    _checkAutoTransition();
    notifyListeners();
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
    _state = _state.copyWith(
      hunger: 100,
      status: PetStatus.eating,
      affection: _state.affection + 10,
      totalInteractions: _state.totalInteractions + 1,
    );
    notifyListeners();
  }

  void play() {
    _state = _state.copyWith(
      mood: 100,
      status: PetStatus.happy,
      affection: _state.affection + 20,
      totalInteractions: _state.totalInteractions + 1,
    );
    notifyListeners();
  }

  void chat() {
    _state = _state.copyWith(
      status: PetStatus.talking,
      affection: _state.affection + 5,
      totalInteractions: _state.totalInteractions + 1,
    );
    notifyListeners();
  }

  void sleep() {
    _state = _state.copyWith(status: PetStatus.sleeping);
    notifyListeners();
  }

  void stopChatting() {
    if (_state.status == PetStatus.talking) {
      _state = _state.copyWith(status: PetStatus.idle);
      notifyListeners();
    }
  }

  // ── 状态恢复 ──

  void restoreFromState(PetState saved) {
    _state = saved;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
