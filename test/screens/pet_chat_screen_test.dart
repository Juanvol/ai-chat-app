// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/screens/pet_chat_screen.dart';

void main() {
  testWidgets('渲染空状态', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetChatScreen()));
    await tester.pump();
    expect(find.text('开始和糯糯聊天吧~'), findsOneWidget);
  });

  testWidgets('有输入框和发送按钮', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetChatScreen()));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });
}
