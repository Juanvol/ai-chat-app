// Flutter 3.24 / Dart 3.5
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class PetChatService extends ChangeNotifier {
  static const _chatsBox = 'pet_chats';
  static const _memBox = 'pet_memories';
  String? _currentId;
  static int _idCounter = 0;
  static int _memIdCounter = 0;
  static final String _sessionPrefix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  Future<void>? _addLock; // 防止 addMessage 并行读写覆盖

  String? get currentId => _currentId;

  Future<Box> get _chats => Hive.openBox(_chatsBox);
  Future<Box> get _mems => Hive.openBox(_memBox);

  Future<void> init() async {
    try {
      final box = await _chats;
      _currentId = box.get('currentId') as String?;
    } catch (_) {}
  }

  Future<String> createChat() async {
    final box = await _chats;
    final id = '${_sessionPrefix}_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';
    await box.put(id, {
      'id': id,
      'title': '新对话',
      'messages': <Map<String, dynamic>>[],
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
    _currentId = id;
    await box.put('currentId', id);
    notifyListeners();
    return id;
  }

  Future<Map<String, dynamic>?> getChat(String id) async {
    final box = await _chats;
    final raw = box.get(id);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<void> addMessage(String chatId, String role, String content) async {
    // 等待上一 addMessage 完成，防并行读写覆盖
    while (_addLock != null) {
      try { await _addLock; } catch (_) {}
    }
    _addLock = _doAddMessage(chatId, role, content);
    try {
      await _addLock;
    } finally {
      _addLock = null;
    }
  }

  Future<void> _doAddMessage(String chatId, String role, String content) async {
    final box = await _chats;
    final chat = await getChat(chatId);
    if (chat == null) return;
    final messages = List<Map<String, dynamic>>.from(chat['messages'] as List? ?? []);
    messages.add({
      'role': role,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    });
    String title = chat['title'] as String? ?? '新对话';
    if (title == '新对话' && role == 'user') {
      title = content.length > 15 ? '${content.substring(0, 15)}...' : content;
    }
    await box.put(chatId, {
      ...chat,
      'title': title,
      'messages': messages,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  Future<void> renameChat(String id, String title) async {
    final box = await _chats;
    final chat = await getChat(id);
    if (chat == null) return;
    await box.put(id, {...chat, 'title': title});
    notifyListeners();
  }

  Future<void> deleteChat(String id) async {
    final box = await _chats;
    await box.delete(id);
    if (_currentId == id) {
      // 从剩下的 key 中找第一个可用 chat
      String? fallbackId;
      for (final key in box.keys) {
        if (key is String && key != 'currentId') {
          fallbackId = key;
          break;
        }
      }
      _currentId = fallbackId;
      if (_currentId != null) {
        await box.put('currentId', _currentId);
      } else {
        await box.delete('currentId');
      }
    }
    notifyListeners();
  }

  Future<void> switchChat(String id) async {
    _currentId = id;
    final box = await _chats;
    await box.put('currentId', id);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> listChats() async {
    final box = await _chats;
    final all = box.values
        .whereType<Map>()
        .where((m) => m['id'] != null && m['id'] != 'currentId')
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    all.sort((a, b) {
      final aTime = DateTime.tryParse('${a['updatedAt'] ?? ''}') ?? DateTime(2000);
      final bTime = DateTime.tryParse('${b['updatedAt'] ?? ''}') ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });
    return all;
  }

  Future<String> buildContext(String chatId, {int maxRounds = 3}) async {
    final chat = await getChat(chatId);
    if (chat == null) return '';
    final messages = List<Map<String, dynamic>>.from(chat['messages'] as List? ?? []);
    final recent = messages.reversed.take(maxRounds * 2).toList().reversed.toList();
    return recent.map((m) => '${m['role'] == 'user' ? '主人' : '糯糯'}: ${m['content']}').join('\n');
  }

  Future<int> importMemories(List<Map<String, dynamic>> summaries) async {
    final box = await _mems;
    int count = 0;
    for (final summary in summaries) {
      final id = '${_sessionPrefix}_${DateTime.now().microsecondsSinceEpoch}_${_memIdCounter++}';
      await box.put(id, {
        'id': id,
        'content': summary['summary'] as String? ?? '',
        'context': 'imported:${summary['id'] ?? ''}',
        'sourceTitle': summary['title'] as String? ?? '未知对话',
        'importedAt': DateTime.now().toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
      });
      count++;
    }
    notifyListeners();
    return count;
  }

  Future<List<Map<String, dynamic>>> listMemories() async {
    final box = await _mems;
    return box.values
        .whereType<Map>()
        .where((m) => m['id'] != null && m['id'] != 'imports')
        .map((m) => Map<String, dynamic>.from(m))
        .toList()
      ..sort((a, b) {
        final aTime = DateTime.tryParse('${a['importedAt'] ?? a['createdAt'] ?? ''}') ?? DateTime(2000);
        final bTime = DateTime.tryParse('${b['importedAt'] ?? b['createdAt'] ?? ''}') ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });
  }

  Future<void> deleteMemory(String id) async {
    final box = await _mems;
    await box.delete(id);
    notifyListeners();
  }
}
