// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/models/message.dart';
import 'package:deepseek_chat/widgets/chat_bubble.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ChatBubble', () {
    testWidgets('用户消息右对齐', (tester) async {
      final msg = Message(id: '1', role: 'user', content: '你好', createdAt: DateTime.now());
      await tester.pumpWidget(_wrap(ChatBubble(msg: msg)));

      final row = tester.widget<Row>(find.byType(Row).first);
      expect(row.mainAxisAlignment, MainAxisAlignment.end);
    });

    testWidgets('AI 消息左对齐', (tester) async {
      final msg = Message(id: '1', role: 'assistant', content: '你好', createdAt: DateTime.now());
      await tester.pumpWidget(_wrap(ChatBubble(msg: msg)));

      final row = tester.widget<Row>(find.byType(Row).first);
      expect(row.mainAxisAlignment, MainAxisAlignment.start);
    });

    testWidgets('用户消息显示内容', (tester) async {
      final msg = Message(id: '1', role: 'user', content: 'Hello World', createdAt: DateTime.now());
      await tester.pumpWidget(_wrap(ChatBubble(msg: msg)));

      expect(find.text('Hello World'), findsOneWidget);
    });

    testWidgets('AI 消息渲染 Markdown 粗体', (tester) async {
      final msg = Message(id: '1', role: 'assistant', content: '**bold**', createdAt: DateTime.now());
      await tester.pumpWidget(_wrap(ChatBubble(msg: msg)));

      expect(find.text('bold'), findsOneWidget);
    });

    testWidgets('streaming 消息显示三点动画', (tester) async {
      final msg = Message(id: '1', role: 'assistant', content: '', createdAt: DateTime.now(), isStreaming: true);
      await tester.pumpWidget(_wrap(ChatBubble(msg: msg)));

      // 三点动画由 _ThreeDots 渲染 —— 3 个 _Dot
      expect(find.byType(ChatBubble), findsOneWidget);
    });

    testWidgets('深度思考卡片显示已深度思考标签', (tester) async {
      final msg = Message(id: '1', role: 'assistant',
        content: '回答内容', reasoningContent: '思考过程',
        createdAt: DateTime.now(),
      );
      await tester.pumpWidget(_wrap(ChatBubble(msg: msg)));

      // 非 streaming 时显示"已深度思考"标签（含用时）
      expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
    });

    testWidgets('dislike 按钮在 AI 消息非 streaming 时显示', (tester) async {
      bool disliked = false;
      final msg = Message(id: '1', role: 'assistant', content: '回答', createdAt: DateTime.now());
      await tester.pumpWidget(_wrap(ChatBubble(msg: msg, onDislike: () => disliked = true)));

      await tester.tap(find.byIcon(Icons.thumb_down_outlined));
      await tester.pumpAndSettle();

      expect(disliked, true);
    });

    testWidgets('复制按钮需要 onDislike 才显示', (tester) async {
      final msg = Message(id: '1', role: 'assistant', content: '可复制', createdAt: DateTime.now());
      // 无 onDislike 时不显示操作按钮
      await tester.pumpWidget(_wrap(ChatBubble(msg: msg)));
      expect(find.byIcon(Icons.copy_outlined), findsNothing);

      // 有 onDislike 时显示操作按钮
      await tester.pumpWidget(_wrap(ChatBubble(msg: msg, onDislike: () {})));
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    });
  });
}
