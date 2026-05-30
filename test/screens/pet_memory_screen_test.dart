// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/screens/pet_memory_screen.dart';

void main() {
  testWidgets('渲染空状态', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetMemoryScreen()));
    await tester.pump();
    expect(find.text('还没有记忆，去和糯糯聊天或分享对话吧~'), findsOneWidget);
  });

  testWidgets('有导入按钮', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetMemoryScreen()));
    await tester.pump();
    expect(find.byIcon(Icons.file_download), findsOneWidget);
  });
}
