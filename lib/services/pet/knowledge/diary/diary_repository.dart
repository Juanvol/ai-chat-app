// Flutter 3.24 / Dart 3.5
import '../models/diary_entry.dart';

/// 日记持久化接口
/// 后期换 SQLite 只需实现此接口，不改 DiaryStore
abstract class IDiaryRepository {
  Future<void> save(DiaryEntry entry);

  /// 加载某天的所有条目（按时间升序）
  Future<List<DiaryEntry>> loadByDate(DateTime date);

  /// 加载最近 N 天条目
  Future<List<DiaryEntry>> loadRecent({int days = 7});

  /// 加载某天的日总结（如有）
  Future<DiaryEntry?> loadSummary(DateTime date);

  Future<void> delete(String id);

  Future<void> clearAll();

  /// 实时监听新条目
  Stream<DiaryEntry> watch();
}
