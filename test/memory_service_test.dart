// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/services/memory_service.dart';
import 'fake_storage_service.dart';

void main() {
  late FakeStorageService storage;
  late MemoryService svc;

  setUp(() {
    storage = FakeStorageService();
    svc = MemoryService(storage: storage);
  });

  group('MemoryService', () {
    test('初始化 memories 为空', () {
      expect(svc.memories, isEmpty);
    });

    test('promptText 空时返回空字符串', () {
      expect(svc.promptText, '');
    });

    test('add 添加记忆后列表包含新条目', () async {
      await svc.add('用户叫张三', importance: 4, tags: ['name']);
      expect(svc.memories.length, 1);
      expect(svc.memories.first.content, '用户叫张三');
      expect(svc.memories.first.importance, 4);
      expect(svc.memories.first.tags, ['name']);
    });

    test('promptText 拼接多条记忆', () async {
      await svc.add('喜欢Python');
      await svc.add('住北京');
      final pt = svc.promptText;
      expect(pt, contains('- 喜欢Python'));
      expect(pt, contains('- 住北京'));
    });

    test('update 修改内容', () async {
      await svc.add('原始内容');
      final id = svc.memories.first.id;
      await svc.update(id, content: '修改后', importance: 5);
      expect(svc.memories.first.content, '修改后');
      expect(svc.memories.first.importance, 5);
    });

    test('delete 删除记忆', () async {
      await svc.add('test1');
      await Future.delayed(const Duration(milliseconds: 5));
      await svc.add('test2');
      await svc.delete(svc.memories.first.id);
      expect(svc.memories.length, 1);
    });
  });
}
