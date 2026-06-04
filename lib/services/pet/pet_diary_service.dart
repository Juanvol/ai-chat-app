// Flutter 3.24 / Dart 3.5
// ignore_for_file: must_call_super
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'pet_logger.dart';

/// 宠物日记持久化服务（单例）
/// 自动记录：喂食、抚摸、说话、睡觉/醒来、心情变化等事件
class PetDiaryService extends ChangeNotifier {
  static final PetDiaryService instance = PetDiaryService._();
  PetDiaryService._();

  static const _boxName = 'pet_diary';
  static int _idCounter = 0;
  static final String _sessionPrefix =
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  List<Map<String, dynamic>> _entries = [];
  bool _loaded = false;

  List<Map<String, dynamic>> get entries => List.unmodifiable(_entries);

  @override
  void dispose() {
    // 单例 — 不由 Provider dispose，生命周期跟随应用进程
  }

  Future<Box> get _box => Hive.openBox(_boxName);

  Future<void> init() async {
    if (_loaded) return;
    try {
      final box = await _box;
      _entries = box.values
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      _entries.sort((a, b) {
        final aTime =
            DateTime.tryParse('${a['date'] ?? ''}') ?? DateTime(2000);
        final bTime =
            DateTime.tryParse('${b['date'] ?? ''}') ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });
    } catch (_) {}
    _loaded = true;
  }

  /// 自动记录一条日记事件
  Future<void> addEntry({
    required String content,
    String mood = '📝',
    String type = 'manual',
  }) async {
    final id =
        '${_sessionPrefix}_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';
    final entry = {
      'id': id,
      'content': content,
      'mood': mood,
      'type': type,
      'date': DateTime.now().toIso8601String(),
    };
    _entries.insert(0, entry);
    try {
      final box = await _box;
      await box.put(id, entry);
    } catch (e) {
      PetLogger().error('PetDiary', 'save failed', e);
    }
    notifyListeners();
    PetLogger().trace('PetDiary', 'entry added: $content');
  }

  /// 记录宠物互动事件（由 overlay host 调用）
  Future<void> recordEvent(String type, {String? detail}) async {
    final (content, mood) = switch (type) {
      'tap' => ('被主人轻轻戳了一下~', '😊'),
      'longPress' => ('享受了主人给的零食，好吃好吃~ 😋', '😋'),
      'feed' => ('吃了一顿美味大餐~', '😋'),
      'talk' => ('和主人聊了会天~', '💬'),
      'sleep' => ('糯糯睡着了...zzZ', '💤'),
      'wake' => ('糯糯醒啦，又是元气满满的一天~', '😸'),
      'suggestion' => (detail ?? '给了主人一个小建议', '💡'),
      'lowEnergy' => ('能量不足，糯糯好累...', '😞'),
      'lowHunger' => ('肚子饿了，想吃东西...', '🍖'),
      _ => (detail ?? '发生了某件事', '📝'),
    };
    await addEntry(content: content, mood: mood, type: type);
  }

  Future<void> deleteEntry(String id) async {
    _entries.removeWhere((e) => e['id'] == id);
    try {
      final box = await _box;
      await box.delete(id);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> clearAll() async {
    _entries.clear();
    try {
      final box = await _box;
      await box.clear();
    } catch (_) {}
    notifyListeners();
  }
}
