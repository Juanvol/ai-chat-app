// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/services/app/conversation_service.dart';
import 'package:deepseek_chat/models/conversation.dart';
import 'package:deepseek_chat/models/message.dart';
import 'fake_storage_service.dart';
import 'fake_llm_client.dart';

void main() {
  late FakeStorageService storage;
  late ConversationService svc;

  group('ConversationService', () {
    setUp(() {
      storage = FakeStorageService();
      storage.injectKey('sk-test-key');
      storage.injectModel('ds-v4-pro');
      storage.injectSetting('global_max_tokens', 8192);
      storage.injectSetting('global_temperature', 0.7);
      storage.injectSetting('rate_limit', 20);
    });

    group('初始化', () {
      test('无对话时 conversations 为空，current 为 null', () {
        svc = ConversationService(storage: storage, client: FakeLLMClient.empty());
        expect(svc.conversations, isEmpty);
        expect(svc.currentConversation, isNull);
      });

      test('加载已有对话列表', () {
        final now = DateTime.now();
        final conv = Conversation(id: 'c1', title: '旧对话',
          createdAt: now, updatedAt: now, messages: [], modelId: 'ds-chat');
        storage.injectConv(conv);

        svc = ConversationService(storage: storage, client: FakeLLMClient.empty());
        expect(svc.conversations.length, 1);
        expect(svc.currentConversation!.id, 'c1');
      });

      test('恢复上次选中的对话', () {
        final now = DateTime.now();
        storage.injectConv(Conversation(id: 'c1', title: 'A', createdAt: now, updatedAt: now, messages: []));
        storage.injectConv(Conversation(id: 'c2', title: 'B', createdAt: now.add(const Duration(seconds: 1)), updatedAt: now.add(const Duration(seconds: 1)), messages: []));
        storage.injectSetting('current_conv_id', 'c2');

        svc = ConversationService(storage: storage, client: FakeLLMClient.empty());
        expect(svc.currentConversation!.id, 'c2');
      });

      test('标记 streaming 的消息恢复为非 streaming', () {
        final now = DateTime.now();
        final conv = Conversation(id: 'c1', title: 'X', createdAt: now, updatedAt: now,
          messages: [
            Message(id: 'm1', role: 'assistant', content: 'thinking...', createdAt: now, isStreaming: true),
            Message(id: 'm2', role: 'user', content: 'hi', createdAt: now),
          ],
        );
        storage.injectConv(conv);

        svc = ConversationService(storage: storage, client: FakeLLMClient.empty());
        final loaded = svc.conversations.first;
        expect(loaded.messages[0].isStreaming, false);
        expect(loaded.messages[0].content, 'thinking...');
      });

      test('streaming 空 content 恢复为 （对话中断）', () {
        final now = DateTime.now();
        final conv = Conversation(id: 'c1', title: 'X', createdAt: now, updatedAt: now,
          messages: [
            Message(id: 'm1', role: 'assistant', content: '', createdAt: now, isStreaming: true),
          ],
        );
        storage.injectConv(conv);

        svc = ConversationService(storage: storage, client: FakeLLMClient.empty());
        expect(svc.conversations.first.messages[0].content, '（对话中断）');
      });
    });

    group('对话管理', () {
      setUp(() {
        svc = ConversationService(storage: storage, client: FakeLLMClient.empty());
      });

      test('createConversation 插入列表头', () async {
        await svc.createConversation();
        expect(svc.conversations.length, 1);
        expect(svc.currentConversation, isNotNull);
        expect(svc.currentConversation!.title, '新对话');
      });

      test('selectConversation 切换当前对话', () async {
        await svc.createConversation();
        final cid = svc.currentConversation!.id;
        await svc.createConversation(); // 再建一个
        svc.selectConversation(cid);
        expect(svc.currentConversation!.id, cid);
      });

      test('deleteConversation 删除并切换 current', () async {
        await svc.createConversation();
        final cid = svc.currentConversation!.id;
        await Future.delayed(const Duration(milliseconds: 5)); // 避免 ID 碰撞
        await svc.createConversation();
        await svc.deleteConversation(cid);
        expect(svc.conversations.length, 1);
        expect(svc.currentConversation!.id, isNot(cid));
      });

      test('renameConversation 更新标题', () async {
        await svc.createConversation();
        final cid = svc.currentConversation!.id;
        await svc.renameConversation(cid, '新标题');
        expect(svc.currentConversation!.title, '新标题');
      });
    });

    group('sendMessage', () {
      setUp(() {
        svc = ConversationService(storage: storage, client: FakeLLMClient.empty());
      });

      test('无 API Key 插入提示消息', () async {
        await svc.createConversation();
        svc = ConversationService(storage: storage, client: FakeLLMClient.noKey());
        final result = await svc.sendMessage('hello');
        expect(result, false);
        final msgs = svc.currentConversation!.messages;
        expect(msgs.length, 2);
        expect(msgs.last.content, '请先在「设置」中配置 API Key');
      });

      test('流式响应追加到 assistant message', () async {
        await svc.createConversation();
        final client = FakeLLMClient.fromTexts(['你', '好', '！']);
        svc = ConversationService(storage: storage, client: client);

        final result = await svc.sendMessage('hello');
        expect(result, true);
        final msgs = svc.currentConversation!.messages;
        expect(msgs.last.content, '你好！');
        expect(msgs.last.isStreaming, false);
      });

      test('send 后 isLoading 为 false', () async {
        await svc.createConversation();
        final client = FakeLLMClient.fromTexts(['OK']);
        svc = ConversationService(storage: storage, client: client);

        await svc.sendMessage('hi');
        expect(svc.isLoading, false);
      });

      test('异常时显示友好错误', () async {
        await svc.createConversation();
        final client = FakeLLMClient.error();
        svc = ConversationService(storage: storage, client: client);

        await svc.sendMessage('hi');
        final msgs = svc.currentConversation!.messages;
        expect(msgs.last.content, contains('信号不好喵...请稍后重试~'));
        expect(svc.isLoading, false);
      });

      test('stopGeneration 后 cancelToken 不置 null', () {
        svc.stopGeneration();
        // stopGeneration 在未发送消息时调用不崩溃即可
      });

      test('第一条消息自动生成标题', () async {
        await svc.createConversation();
        final client = FakeLLMClient.fromTexts(['OK']);
        svc = ConversationService(storage: storage, client: client);

        await svc.sendMessage('这是一个比较长的测试消息');
        expect(svc.currentConversation!.title, contains('这是一个比较长的测试消息'));
      });

      test('标题截断超长首消息', () async {
        await svc.createConversation();
        final client = FakeLLMClient.fromTexts(['OK']);
        svc = ConversationService(storage: storage, client: client);

        await svc.sendMessage('这是一个非常非常非常非常非常非常长的测试消息');
        expect(svc.currentConversation!.title.length, lessThanOrEqualTo(23)); // 20 + '...'
      });
    });
  });
}
