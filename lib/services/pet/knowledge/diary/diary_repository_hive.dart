// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'package:hive/hive.dart';
import 'diary_repository.dart';
import '../../pet_logger.dart';
import '../models/diary_entry.dart';

class DiaryRepoHive implements IDiaryRepository {
  static const _boxName = 'pet_diary_v2';
  bool _initialized = false;

  final StreamController<DiaryEntry> _watchCtrl =
      StreamController<DiaryEntry>.broadcast();

  Future<Box> get _box => Hive.openBox(_boxName);

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _box;
      _initialized = true;
    } catch (e) {
      PetLogger().error('DiaryRepoHive', 'init failed', e);
    }
  }

  @override
  Future<void> save(DiaryEntry entry) async {
    try {
      final box = await _box;
      await box.put(entry.id, entry.toJson());
      _watchCtrl.add(entry);
    } catch (e) {
      PetLogger().error('DiaryRepoHive', 'save failed', e);
    }
  }

  @override
  Future<List<DiaryEntry>> loadByDate(DateTime date) async {
    try {
      final box = await _box;
      final dateStr = _dateKey(date);
      return box.values
          .whereType<Map>()
          .map((m) => DiaryEntry.fromJson(Map<String, dynamic>.from(m)))
          .where((e) => e.dateKey != null && _dateKey(e.dateKey!) == dateStr)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
    } catch (e) {
      PetLogger().error('DiaryRepoHive', 'loadByDate failed', e);
      return [];
    }
  }

  @override
  Future<List<DiaryEntry>> loadRecent({int days = 7}) async {
    try {
      final box = await _box;
      final cutoff = DateTime.now().subtract(Duration(days: days));
      return box.values
          .whereType<Map>()
          .map((m) => DiaryEntry.fromJson(Map<String, dynamic>.from(m)))
          .where((e) => e.date.isAfter(cutoff))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      PetLogger().error('DiaryRepoHive', 'loadRecent failed', e);
      return [];
    }
  }

  @override
  Future<DiaryEntry?> loadSummary(DateTime date) async {
    final entries = await loadByDate(date);
    return entries.cast<DiaryEntry?>().firstWhere(
          (e) => e!.type == DiaryEntryType.summary,
          orElse: () => null,
        );
  }

  @override
  Future<void> delete(String id) async {
    try {
      final box = await _box;
      await box.delete(id);
    } catch (e) {
      PetLogger().error('DiaryRepoHive', 'delete failed', e);
    }
  }

  @override
  Future<void> clearAll() async {
    try {
      final box = await _box;
      await box.clear();
    } catch (e) {
      PetLogger().error('DiaryRepoHive', 'clearAll failed', e);
    }
  }

  @override
  Stream<DiaryEntry> watch() => _watchCtrl.stream;

  void dispose() {
    _watchCtrl.close();
  }

  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
