// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import '../../lib/services/pet_chat_service.dart';

void main() {
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('pet_chat_test_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
  });

  group('PetChatService', () {
    test('createChat 创建新对话', () async {
      final svc = PetChatService();
      final id = await svc.createChat();
      expect(id, isNotEmpty);
      expect(svc.currentId, id);
    });

    test('createChat 自动标题', () async {
      final svc = PetChatService();
      final id = await svc.createChat();
      final chat = await svc.getChat(id);
      expect(chat!['title'], '新对话');
    });

    test('addMessage 追加并更新标题', () async {
      final svc = PetChatService();
      final id = await svc.createChat();
      await svc.addMessage(id, 'user', '今天天气真好喵~');
      await svc.addMessage(id, 'assistant', '是的主人！');
      final chat = await svc.getChat(id);
      final msgs = chat!['messages'] as List;
      expect(msgs.length, 2);
    });

    test('renameChat', () async {
      final svc = PetChatService();
      final id = await svc.createChat();
      await svc.renameChat(id, '自定义标题');
      final chat = await svc.getChat(id);
      expect(chat!['title'], '自定义标题');
    });

    test('deleteChat 后 currentId 切换', () async {
      final svc = PetChatService();
      final id1 = await svc.createChat();
      final id2 = await svc.createChat();
      await svc.deleteChat(id2);
      expect(svc.currentId, id1);
    });

    test('switchChat', () async {
      final svc = PetChatService();
      final id1 = await svc.createChat();
      final id2 = await svc.createChat();
      await svc.switchChat(id1);
      expect(svc.currentId, id1);
    });

    test('listChats 排序', () async {
      final svc = PetChatService();
      await svc.createChat();
      await Future.delayed(const Duration(milliseconds: 10));
      await svc.createChat();
      final list = await svc.listChats();
      expect(list.length, 2);
    });

    test('importMemories 批量导入', () async {
      final svc = PetChatService();
      final count = await svc.importMemories([
        {'id': 'conv-1', 'title': '数学讨论', 'summary': '讨论微积分'},
        {'id': 'conv-2', 'title': '编程帮助', 'summary': 'Flutter 问题'},
      ]);
      expect(count, 2);
      final memories = await svc.listMemories();
      expect(memories.length, 2);
    });

    test('deleteMemory', () async {
      final svc = PetChatService();
      await svc.importMemories([
        {'id': 'conv-1', 'title': '测试', 'summary': '测试内容'},
      ]);
      final memories = await svc.listMemories();
      await svc.deleteMemory(memories.first['id'] as String);
      expect((await svc.listMemories()).length, 0);
    });

    test('buildContext 拼接上下文', () async {
      final svc = PetChatService();
      final id = await svc.createChat();
      await svc.addMessage(id, 'user', '你好');
      await svc.addMessage(id, 'assistant', '喵~你好主人！');
      final ctx = await svc.buildContext(id, maxRounds: 1);
      expect(ctx, contains('你好'));
      expect(ctx, contains('喵~'));
    });
  });
}
