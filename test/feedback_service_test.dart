// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/services/app/feedback_service.dart';
import 'fake_storage_service.dart';
import 'fake_llm_client.dart';

void main() {
  late FakeStorageService storage;
  late FeedbackService svc;

  setUp(() {
    storage = FakeStorageService();
    svc = FeedbackService(storage: storage);
  });

  group('FeedbackService', () {
    test('初始化 entries 为空', () {
      expect(svc.entries, isEmpty);
    });

    test('add 添加反馈', () async {
      await svc.add(
        conversationId: 'c1', userMessage: '你好',
        aiResponse: '你好！', reason: '跑题',
      );
      expect(svc.entries.length, 1);
      expect(svc.entries.first.reason, '跑题');
      expect(svc.entries.first.processed, false);
    });

    test('unprocessed 仅返回未处理的', () async {
      await svc.add(conversationId: 'c1', userMessage: 'a', aiResponse: 'b');
      await svc.add(conversationId: 'c1', userMessage: 'c', aiResponse: 'd');
      // 手动标记第一条为 processed
      svc.entries[0].processed = true;
      expect(svc.unprocessed.length, 1);
      expect(svc.unprocessedCount, 1);
    });

    test('updateReason 修改原因', () async {
      await svc.add(conversationId: 'c1', userMessage: 'a', aiResponse: 'b');
      await svc.updateReason(svc.entries.first.id, '不准确');
      expect(svc.entries.first.reason, '不准确');
    });

    test('delete 删除反馈', () async {
      await svc.add(conversationId: 'c1', userMessage: 'a', aiResponse: 'b');
      await svc.delete(svc.entries.first.id);
      expect(svc.entries, isEmpty);
    });

    test('adjustmentText 读写', () async {
      await svc.saveAdjustmentText('修正：不要太啰嗦');
      expect(svc.adjustmentText, '修正：不要太啰嗦');
    });

    test('autoGenerate 标记所有 pending 为 processed', () async {
      await svc.add(conversationId: 'c1', userMessage: 'a', aiResponse: 'b');
      await svc.add(conversationId: 'c1', userMessage: 'c', aiResponse: 'd');
      await svc.autoGenerate(
        client: FakeLLMClient.text('### 修正指令\n修复\n### 问题摘要\ntest'),
        apiKey: 'x',
      );
      expect(svc.unprocessedCount, 0);
    });
  });
}
