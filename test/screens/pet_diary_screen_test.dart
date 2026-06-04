// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:deepseek_chat/screens/pet/pet_diary_screen.dart';
import 'package:deepseek_chat/services/pet/pet_diary_service.dart';

void main() {
  late Directory tmpDir;

  setUpAll(() {
    tmpDir = Directory.systemTemp.createTempSync('pet_diary_test');
    Hive.init(tmpDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    tmpDir.deleteSync(recursive: true);
  });

  testWidgets('渲染空状态和添加按钮', (tester) async {
    final svc = PetDiaryService.instance;
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<PetDiaryService>.value(
          value: svc,
          child: const PetDiaryScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('📖'), findsOneWidget);
    expect(find.text('还没有日记条目~'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
