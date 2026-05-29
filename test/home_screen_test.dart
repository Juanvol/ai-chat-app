// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:deepseek_chat/screens/home_screen.dart';
import 'package:deepseek_chat/services/conversation_service.dart';
import 'package:deepseek_chat/services/memory_service.dart';
import 'package:deepseek_chat/services/persona_service.dart';
import 'package:deepseek_chat/services/feedback_service.dart';
import 'fake_storage_service.dart';
import 'fake_llm_client.dart';

Widget _wrapHome({ConversationService? svc}) {
  final storage = FakeStorageService();
  storage.injectKey('sk-test');
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(
        value: svc ?? ConversationService(storage: storage, client: FakeLLMClient.empty()),
      ),
      ChangeNotifierProvider(create: (_) => MemoryService(storage: storage)),
      ChangeNotifierProvider(create: (_) => PersonaService(storage: storage)),
      ChangeNotifierProvider(create: (_) => FeedbackService(storage: storage)),
    ],
    child: const MaterialApp(home: HomeScreen()),
  );
}

void main() {
  group('HomeScreen', () {
    testWidgets('无对话时显示欢迎页和建议问题', (tester) async {
      await tester.pumpWidget(_wrapHome());

      expect(find.text('AI 助手'), findsOneWidget);
      expect(find.text('写一个快速排序算法'), findsOneWidget);
      expect(find.text('推荐 5 本经典小说'), findsOneWidget);
    });

    testWidgets('有对话时显示聊天视图', (tester) async {
      final storage = FakeStorageService();
      storage.injectKey('sk-test');
      final svc = ConversationService(storage: storage, client: FakeLLMClient.empty());
      await svc.createConversation();

      await tester.pumpWidget(_wrapHome(svc: svc));

      // AppBar 显示对话标题
      expect(find.text('新对话'), findsWidgets);
      // 显示输入框
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Drawer 包含导航项', (tester) async {
      await tester.pumpWidget(_wrapHome());

      // 打开 Drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('任务上下文'), findsOneWidget);
      expect(find.text('人格管理'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
    });

    testWidgets('点击建议问题创建对话并发送', (tester) async {
      final storage = FakeStorageService();
      storage.injectKey('sk-test');
      final svc = ConversationService(storage: storage, client: FakeLLMClient.empty());

      await tester.pumpWidget(_wrapHome(svc: svc));
      await tester.tap(find.text('写一个快速排序算法'));
      await tester.pumpAndSettle();

      // 创建了对话
      expect(svc.conversations.length, 1);
      expect(svc.currentConversation, isNotNull);
    });
  });
}
