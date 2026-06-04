// Flutter 3.24 / Dart 3.5
import '../models/memory_entry.dart';

/// 记忆持久化接口
abstract class IMemoryRepository {
  Future<void> save(MemoryEntry entry);

  Future<void> saveAll(List<MemoryEntry> entries);

  Future<List<MemoryEntry>> loadAll({MemoryTag? tag});

  /// 内容关键词检索
  Future<List<MemoryEntry>> search(String keyword);

  Future<void> delete(String id);

  Future<void> update(String id, MemoryEntry entry);

  Future<void> clearAll();

  /// 实时监听记忆变更
  Stream<List<MemoryEntry>> watch();
}
