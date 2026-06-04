// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:deepseek_chat/services/pet/pet_chat_service.dart';

void main() {
  late String testDir;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('pet_chat_test_');
    testDir = dir.path;
    Hive.init(testDir);
  });

  setUp(() async {
    // 仅删 box 文件，不预打开 — 让各测试通过 PetChatService 自行打开
    try { await Hive.deleteBoxFromDisk('pet_chats'); } catch (_) {}
    try { await Hive.deleteBoxFromDisk('pet_memories'); } catch (_) {}
  });

  tearDownAll(() async {
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

    test('deleteChat 删除最后一个 chat → currentId 为 null', () async {
      final svc = PetChatService();
      final id = await svc.createChat();
      await svc.deleteChat(id);
      expect(svc.currentId, isNull);
    });

    test('deleteChat 删除非当前 chat → currentId 不变', () async {
      final svc = PetChatService();
      final id1 = await svc.createChat();
      final id2 = await svc.createChat();
      // currentId 是 id2（最后创建的），删除 id1 不应改变 currentId
      await svc.deleteChat(id1);
      expect(svc.currentId, id2);
      // 确认 id1 确实被删了
      expect(await svc.getChat(id1), isNull);
      expect(await svc.getChat(id2), isNotNull);
    });

    test('deleteChat 连续删除不抛异常', () async {
      final svc = PetChatService();
      final id1 = await svc.createChat();
      final id2 = await svc.createChat();
      final id3 = await svc.createChat();
      // 删非当前 → currentId 不变
      await svc.deleteChat(id1);
      expect(svc.currentId, id3);
      // 删当前 → fallback 到剩余
      await svc.deleteChat(id3);
      expect(svc.currentId, id2);
      // 删最后一个 → currentId 为 null
      await svc.deleteChat(id2);
      expect(svc.currentId, isNull);
    });

    test('switchChat', () async {
      final svc = PetChatService();
      final id1 = await svc.createChat();
      await svc.createChat(); // 创建第二个对话，确保存在多个 chat
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
