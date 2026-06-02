// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:deepseek_chat/screens/pet_center_screen.dart';
import 'package:deepseek_chat/pet/pet_controller.dart';
import 'package:deepseek_chat/services/pet_token_service.dart';

Widget _wrapWithProviders(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => PetController()),
      ChangeNotifierProvider(create: (_) => PetTokenService()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync();
    Hive.init(tmpDir.path);
  });

  tearDown(() {
    Hive.close();
    tmpDir.deleteSync(recursive: true);
  });

  testWidgets('渲染 4 个 Tab', (tester) async {
    await tester.pumpWidget(_wrapWithProviders(const PetCenterScreen()));
    await tester.pump();
    expect(find.text('💬 聊天'), findsOneWidget);
    expect(find.text('🧠 记忆'), findsOneWidget);
    expect(find.text('📖 日记'), findsOneWidget);
    expect(find.text('⚙️ 设置'), findsOneWidget);
  });

  testWidgets('状态卡片显示宠物名字', (tester) async {
    await tester.pumpWidget(_wrapWithProviders(const PetCenterScreen()));
    await tester.pump();
    expect(find.text('弗糯糯'), findsOneWidget);
  });
}
