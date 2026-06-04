import 'package:flutter/foundation.dart';
import '../models/memory.dart';
import 'storage_service.dart';

class MemoryService extends ChangeNotifier {
  final StorageService _storage;
  List<Memory> _memories = [];

  MemoryService({required StorageService storage})
      : _storage = storage {
    _load();
  }

  List<Memory> get memories => _memories;

  String get promptText {
    if (_memories.isEmpty) return '';
    final items = _memories.map((m) => '- ${m.content}').join('\n');
    return '''## 任务上下文
以下是你与用户协作的已知信息，用于更精准地理解用户的当前目标和问题：

$items

重要：以上信息用于理解任务背景，不是让你迎合用户偏好。你必须保持专业客观，当用户的想法有明确问题时，请直接、礼貌地指出，不要附和。''';
  }

  void _load() {
    _memories = _storage.getMems();
    notifyListeners();
  }

  Future<void> add(String content, {int importance = 3, List<String> tags = const []}) async {
    final now = DateTime.now();
    final m = Memory(id: now.millisecondsSinceEpoch.toString(), content: content,
        importance: importance, createdAt: now, updatedAt: now, tags: tags);
    _memories.insert(0, m);
    await _storage.saveMem(m);
    notifyListeners();
  }

  Future<void> update(String id, {String? content, int? importance, List<String>? tags}) async {
    final i = _memories.indexWhere((m) => m.id == id);
    if (i == -1) return;
    final m = _memories[i];
    if (content != null) m.content = content;
    if (importance != null) m.importance = importance;
    if (tags != null) m.tags = tags;
    m.updatedAt = DateTime.now();
    await _storage.saveMem(m);
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _memories.removeWhere((m) => m.id == id);
    await _storage.delMem(id);
    notifyListeners();
  }
}
