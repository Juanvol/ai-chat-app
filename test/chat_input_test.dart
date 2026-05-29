// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/widgets/chat_input.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ChatInput', () {
    testWidgets('空输入时发送按钮为灰色箭头', (tester) async {
      await tester.pumpWidget(_wrap(ChatInput(onSend: (_) {})));

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('loading 状态显示红色停止按钮', (tester) async {
      await tester.pumpWidget(_wrap(ChatInput(
        onSend: (_) {}, onStop: () {}, loading: true,
      )));

      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    });

    testWidgets('点击发送后回调触发并清空输入框', (tester) async {
      String? sent;
      await tester.pumpWidget(_wrap(ChatInput(onSend: (t) => sent = t)));
      await tester.enterText(find.byType(TextField), '你好');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(sent, '你好');
      expect(find.text('你好'), findsNothing);
    });

    testWidgets('loading 状态点击停止回调触发', (tester) async {
      bool stopped = false;
      await tester.pumpWidget(_wrap(ChatInput(
        onSend: (_) {}, onStop: () => stopped = true, loading: true,
      )));

      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pumpAndSettle();

      expect(stopped, true);
    });
  });
}
