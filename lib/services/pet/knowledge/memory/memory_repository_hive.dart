// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'package:hive/hive.dart';
import 'memory_repository.dart';
import '../../pet_logger.dart';
import '../models/memory_entry.dart';

class MemoryRepoHive implements IMemoryRepository {
  static const _boxName = 'pet_memory_v2';
  bool _initialized = false;

  final StreamController<List<MemoryEntry>> _watchCtrl =
      StreamController<List<MemoryEntry>>.broadcast();

  Future<Box> get _box => Hive.openBox(_boxName);

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _box;
      _initialized = true;
    } catch (e) {
      PetLogger().error('MemoryRepoHive', 'init failed', e);
    }
  }

  @override
  Future<void> save(MemoryEntry entry) async {
    try {
      final box = await _box;
      await box.put(entry.id, entry.toJson());
      _notify(box);
    } catch (e) {
      PetLogger().error('MemoryRepoHive', 'save failed', e);
    }
  }

  @override
  Future<void> saveAll(List<MemoryEntry> entries) async {
    try {
      final box = await _box;
      for (final e in entries) {
        await box.put(e.id, e.toJson());
      }
      _notify(box);
    } catch (e) {
      PetLogger().error('MemoryRepoHive', 'saveAll failed', e);
    }
  }

  @override
  Future<List<MemoryEntry>> loadAll({MemoryTag? tag}) async {
    try {
      final box = await _box;
      var entries = box.values
          .whereType<Map>()
          .map((m) => MemoryEntry.fromJson(Map<String, dynamic>.from(m)));
      if (tag != null) {
        entries = entries.where((e) => e.tag == tag);
      }
      return entries.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      PetLogger().error('MemoryRepoHive', 'loadAll failed', e);
      return [];
    }
  }

  @override
  Future<List<MemoryEntry>> search(String keyword) async {
    try {
      final box = await _box;
      final lower = keyword.toLowerCase();
      return box.values
          .whereType<Map>()
          .map((m) => MemoryEntry.fromJson(Map<String, dynamic>.from(m)))
          .where((e) => e.content.toLowerCase().contains(lower))
          .toList()
        ..sort((a, b) => b.importance.compareTo(a.importance));
    } catch (e) {
      PetLogger().error('MemoryRepoHive', 'search failed', e);
      return [];
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      final box = await _box;
      await box.delete(id);
      _notify(box);
    } catch (e) {
      PetLogger().error('MemoryRepoHive', 'delete failed', e);
    }
  }

  @override
  Future<void> update(String id, MemoryEntry entry) async {
    await save(entry.copyWith(updatedAt: DateTime.now()));
  }

  @override
  Future<void> clearAll() async {
    try {
      final box = await _box;
      await box.clear();
      _notify(box);
    } catch (e) {
      PetLogger().error('MemoryRepoHive', 'clearAll failed', e);
    }
  }

  @override
  Stream<List<MemoryEntry>> watch() => _watchCtrl.stream;

  void dispose() {
    _watchCtrl.close();
  }

  void _notify(Box box) {
    final all = box.values
        .whereType<Map>()
        .map((m) => MemoryEntry.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    _watchCtrl.add(all);
  }
}
