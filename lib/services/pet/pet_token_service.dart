// Flutter 3.24 / Dart 3.5
// ignore_for_file: must_call_super

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../models/pet_token_usage.dart';

class PetTokenService extends ChangeNotifier {
  static const _boxName = 'pet_token';

  /// 共享单例，消除多实例缓存不同步问题
  static final PetTokenService instance = PetTokenService._();

  PetTokenService._();

  int? _dailyBudget = 50000;
  bool _budgetLoaded = false;
  Future<void>? _recordLock;

  int? get dailyBudget => _dailyBudget;
  bool get isUnlimited => _dailyBudget == null;

  @override
  void dispose() {
    // Singleton — 不由 Provider dispose，生命周期跟随应用进程
  }

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

  Future<int?> _readBudget() async {
    try {
      final box = await _box;
      final raw = box.get('budget');
      if (raw is int) return raw;
      return _dailyBudget;
    } catch (_) {
      return _dailyBudget;
    }
  }

  Future<bool> checkBudget() async {
    final budget = await _readBudget();
    if (budget == null) return true;
    final today = await getTodayUsage();
    return today.totalTokens < budget;
  }

  Future<int> getBudgetRemaining() async {
    final budget = await _readBudget();
    if (budget == null) return 999999;
    final today = await getTodayUsage();
    return budget - today.totalTokens;
  }

  Future<double> getBudgetUsageFraction() async {
    final budget = await _readBudget();
    if (budget == null || budget == 0) return 0;
    final today = await getTodayUsage();
    return today.totalTokens / budget;
  }
}
