// Flutter 3.24 / Dart 3.5
import 'package:hive/hive.dart';
import 'models/suggestion.dart';

/// 建议持久化存储 — Hive 实现
///
/// 职责：
/// - 写：去重（同日同文本跳过）
/// - 读：按日期分组查询
/// - 清理：超过 7 天自动删除
class SuggestionStore {
  static const _boxName = 'pet_suggestions';
  static const _maxAge = Duration(days: 7);

  Box? _box;

  Future<Box> get _ensureBox async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox(_boxName);
    return _box!;
  }

  /// 添加建议，返回是否实际写入（false = 同日重复已跳过）
  Future<bool> add(Suggestion suggestion) async {
    final box = await _ensureBox;
    final todayStart = _todayStart();

    // 去重：同日同文本跳过
    for (final v in box.values) {
      final existing = Suggestion.fromJson(Map<String, dynamic>.from(v as Map));
      if (existing.text == suggestion.text &&
          existing.createdAt.isAfter(todayStart)) {
        return false;
      }
    }

    await box.add(suggestion.toJson());
    // 每 10 条触发一次清理
    if (box.length % 10 == 0) {
      await _cleanExpired(box);
    }
    return true;
  }

  /// 获取最近 [days] 天的建议，按时间倒序
  Future<List<Suggestion>> getRecent({int days = 7}) async {
    final box = await _ensureBox;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final result = <Suggestion>[];

    for (final v in box.values) {
      final s = Suggestion.fromJson(Map<String, dynamic>.from(v as Map));
      if (s.createdAt.isAfter(cutoff)) {
        result.add(s);
      }
    }

    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// 按日期分组，key 为 "今天" / "昨天" / "MM月dd日"
  Future<Map<String, List<Suggestion>>> getGrouped({int days = 7}) async {
    final all = await getRecent(days: days);
    final grouped = <String, List<Suggestion>>{};
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    for (final s in all) {
      final key = _dateKey(s.createdAt, todayStart, yesterdayStart);
      grouped.putIfAbsent(key, () => []).add(s);
    }

    return grouped;
  }

  /// 清理超过 7 天的记录，返回删除条数
  Future<int> cleanExpired() async {
    final box = await _ensureBox;
    return _cleanExpired(box);
  }

  Future<int> _cleanExpired(Box box) async {
    final cutoff = DateTime.now().subtract(_maxAge);
    final toRemove = <int>[];

    for (int i = 0; i < box.length; i++) {
      final v = box.getAt(i);
      if (v == null) continue;
      final s = Suggestion.fromJson(Map<String, dynamic>.from(v as Map));
      if (s.createdAt.isBefore(cutoff)) {
        toRemove.add(i);
      }
    }

    // 从后往前删，避免索引偏移
    for (final i in toRemove.reversed) {
      await box.deleteAt(i);
    }

    return toRemove.length;
  }

  /// 全部清除
  Future<void> clear() async {
    final box = await _ensureBox;
    await box.clear();
  }

  /// 获取建议总数
  Future<int> get count async {
    final box = await _ensureBox;
    return box.length;
  }

  // ── 私有工具 ──

  DateTime _todayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _dateKey(DateTime date, DateTime todayStart, DateTime yesterdayStart) {
    final d = DateTime(date.year, date.month, date.day);
    if (d == todayStart) return '今天';
    if (d == yesterdayStart) return '昨天';
    return '${date.month}月${date.day}日';
  }

  void dispose() {
    _box = null;
  }
}
