// Flutter 3.24 / Dart 3.5
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/pet_token_usage.dart';

class PetTokenService extends ChangeNotifier {
  static const _boxName = 'pet_token';
  int? _dailyBudget = 50000;
  bool _budgetLoaded = false;
  Future<void>? _recordLock;

  int? get dailyBudget => _dailyBudget;
  bool get isUnlimited => _dailyBudget == null;

  Future<Box> get _box => Hive.openBox(_boxName);

  Future<void> loadBudget() async {
    if (_budgetLoaded) return;
    try {
      final box = await _box;
      final raw = box.get('budget');
      if (raw != null) {
        _dailyBudget = raw as int?;
      }
    } catch (_) {}
    _budgetLoaded = true;
  }

  Future<void> setBudget(int? tokens) async {
    _dailyBudget = tokens;
    try {
      final box = await _box;
      await box.put('budget', tokens);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> recordTokens({
    int decision = 0,
    int chat = 0,
    int vision = 0,
  }) async {
    // ∑¿÷π≤¢––∂¡–¥∏≤∏«
    while (_recordLock != null) {
      try { await _recordLock; } catch (_) {}
    }
    _recordLock = _recordTokens(decision, chat, vision);
    try { await _recordLock; } finally { _recordLock = null; }
  }

  Future<void> _recordTokens(int decision, int chat, int vision) async {
    final box = await _box;
    final today = PetTokenUsage();
    final existing = box.get(today.dateKey);
    if (existing != null) {
      final current = PetTokenUsage.fromJson(Map<String, dynamic>.from(existing as Map));
      final updated = current.add(decision: decision, chat: chat, vision: vision);
      await box.put(today.dateKey, updated.toJson());
    } else {
      final updated = today.add(decision: decision, chat: chat, vision: vision);
      await box.put(today.dateKey, updated.toJson());
    }
    notifyListeners();
  }

  Future<PetTokenUsage> getTodayUsage() async {
    final box = await _box;
    final today = PetTokenUsage();
    final raw = box.get(today.dateKey);
    if (raw == null) return PetTokenUsage();
    return PetTokenUsage.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<List<PetTokenUsage>> getWeekUsage() async {
    final box = await _box;
    final result = <PetTokenUsage>[];
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final raw = box.get(key);
      if (raw != null) {
        result.add(PetTokenUsage.fromJson(Map<String, dynamic>.from(raw as Map)));
      } else {
        result.add(PetTokenUsage(date: d));
      }
    }
    return result;
  }

  Future<int> getMonthUsage() async {
    final box = await _box;
    int total = 0;
    final now = DateTime.now();
    for (int i = 0; i < now.day; i++) {
      final d = DateTime(now.year, now.month, i + 1);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final raw = box.get(key);
      if (raw != null) {
        total += (raw['totalTokens'] as num?)?.toInt() ?? 0;
      }
    }
    return total;
  }

  Future<bool> checkBudget() async {
    if (_dailyBudget == null) return true;
    final today = await getTodayUsage();
    return today.totalTokens < _dailyBudget!;
  }

  Future<int> getBudgetRemaining() async {
    if (_dailyBudget == null) return 999999;
    final today = await getTodayUsage();
    return _dailyBudget! - today.totalTokens;
  }

  Future<double> getBudgetUsageFraction() async {
    if (_dailyBudget == null || _dailyBudget == 0) return 0;
    final today = await getTodayUsage();
    return today.totalTokens / _dailyBudget!;
  }
}
