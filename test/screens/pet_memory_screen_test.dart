// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:deepseek_chat/screens/pet/pet_memory_screen.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync();
    Hive.init(tmpDir.path);
    // 预创建 pet_memories box，避免 PetChatService 首次访问报错
    await Hive.openBox('pet_memories');
    await Hive.openBox('conversations');
  });

  tearDown(() async {
    await Hive.close();
    tmpDir.deleteSync(recursive: true);
  });

  testWidgets('渲染空状态', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetMemoryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('还没有记忆，去和糯糯聊天或分享对话吧~'), findsOneWidget);
  });

  testWidgets('有导入按钮', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetMemoryScreen()));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.file_download), findsOneWidget);
  });
}
