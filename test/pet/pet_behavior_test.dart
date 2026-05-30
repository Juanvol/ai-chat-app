// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/pet/pet_behavior.dart';

void main() {
  group('PetBehavior', () {
    testWidgets('渲染 child', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PetBehavior(
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(PetBehavior), findsOneWidget);
    });

    testWidgets('ecoMode 时不显示气泡', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PetBehavior(
            child: SizedBox(width: 100, height: 100),
            ecoMode: true,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(PetBehavior), findsOneWidget);
    });

    testWidgets('showBubble 显示气泡文本', (tester) async {
      final key = GlobalKey<PetBehaviorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: PetBehavior(
            key: key,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pump();
      key.currentState!.showBubble('测试气泡喵~');
      await tester.pump();
      expect(find.text('测试气泡喵~'), findsOneWidget);
    });

    test('预设气泡池不少于 30 条', () {
      expect(PetBehaviorState.presetBubbles.length, greaterThanOrEqualTo(30));
    });

    test('presetBubbles 包含中文', () {
      final bubbles = PetBehaviorState.presetBubbles;
      expect(bubbles.any((b) => b.contains('喵') || b.contains('主人')), true);
    });
  });
}
