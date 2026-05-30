// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/screens/pet_diary_screen.dart';

void main() {
  testWidgets('渲染空状态和添加按钮', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetDiaryScreen()));
    await tester.pump();
    expect(find.text('📖'), findsOneWidget);
    expect(find.text('还没有日记条目~'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
