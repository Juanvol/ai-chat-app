// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'pet_window.dart';

// 引擎 #2 入口 → PetForegroundService 通过 DartExecutor 指定此函数
@pragma('vm:entry-point')
void petMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const PetWindow());
}
