// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/screens/pet_center_screen.dart';

void main() {
  testWidgets('渲染 4 个 Tab', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetCenterScreen()));
    await tester.pump();
    expect(find.text('💬 聊天'), findsOneWidget);
    expect(find.text('🧠 记忆'), findsOneWidget);
    expect(find.text('📖 日记'), findsOneWidget);
    expect(find.text('⚙️ 设置'), findsOneWidget);
  });

  testWidgets('状态卡片显示宠物名字', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetCenterScreen()));
    await tester.pump();
    expect(find.text('弗糯糯'), findsOneWidget);
  });
}
