// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/pet/pet_menu.dart';

void main() {
  group('PetMenu', () {
    testWidgets('渲染四个菜单项', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Stack(
          children: [
            const SizedBox(width: 120, height: 120),
            PetMenu(onDismiss: () {}),
          ],
        ),
      ));
      expect(find.text('喂食'), findsOneWidget);
      expect(find.text('玩耍'), findsOneWidget);
      expect(find.text('聊天'), findsOneWidget);
      expect(find.text('睡觉'), findsOneWidget);
    });

    testWidgets('点击喂食触发 onFeed', (tester) async {
      bool fed = false;
      await tester.pumpWidget(MaterialApp(
        home: Stack(
          children: [
            const SizedBox(width: 120, height: 120),
            PetMenu(onFeed: () => fed = true, onDismiss: () {}),
          ],
        ),
      ));
      await tester.tap(find.text('喂食'));
      expect(fed, true);
    });

    testWidgets('点击玩耍触发 onPlay', (tester) async {
      bool played = false;
      await tester.pumpWidget(MaterialApp(
        home: Stack(
          children: [
            const SizedBox(width: 120, height: 120),
            PetMenu(onPlay: () => played = true, onDismiss: () {}),
          ],
        ),
      ));
      await tester.tap(find.text('玩耍'));
      expect(played, true);
    });

    testWidgets('点击背景触发 onDismiss', (tester) async {
      bool dismissed = false;
      await tester.pumpWidget(MaterialApp(
        home: Stack(
          children: [
            const SizedBox(width: 120, height: 120),
            PetMenu(onDismiss: () => dismissed = true),
          ],
        ),
      ));
      // tap outside the bubble on the transparent background
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(dismissed, true);
    });

    testWidgets('未设回调不抛异常', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Stack(
          children: [
            const SizedBox(width: 120, height: 120),
            PetMenu(onDismiss: () {}),
          ],
        ),
      ));
      await tester.tap(find.text('喂食'));
      await tester.tap(find.text('玩耍'));
    });
  });
}
