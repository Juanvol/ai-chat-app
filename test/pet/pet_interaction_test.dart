// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/pet/pet_interaction.dart';

void main() {
  group('PetInteraction', () {
    testWidgets('渲染子组件', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PetInteraction(child: SizedBox(width: 120, height: 120))),
      );
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(PetInteraction), findsOneWidget);
    });

    testWidgets('点击触发 onTap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: PetInteraction(
          onTap: () => tapped = true,
          child: const SizedBox(width: 120, height: 120),
        ),
      ));
      await tester.tap(find.byType(PetInteraction));
      expect(tapped, true);
    });

    testWidgets('双击触发 onDoubleTap', (tester) async {
      bool doubleTapped = false;
      await tester.pumpWidget(MaterialApp(
        home: PetInteraction(
          onDoubleTap: () => doubleTapped = true,
          child: const SizedBox(width: 120, height: 120),
        ),
      ));
      await tester.tap(find.byType(PetInteraction));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(PetInteraction));
      await tester.pumpAndSettle();
      expect(doubleTapped, true);
    });

    testWidgets('长按触发 onLongPress', (tester) async {
      bool longPressed = false;
      await tester.pumpWidget(MaterialApp(
        home: PetInteraction(
          onLongPress: () => longPressed = true,
          child: const SizedBox(width: 120, height: 120),
        ),
      ));
      await tester.longPress(find.byType(PetInteraction));
      expect(longPressed, true);
    });

    testWidgets('未设回调不抛异常', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PetInteraction(child: SizedBox(width: 120, height: 120))),
      );
      await tester.tap(find.byType(PetInteraction));
      await tester.longPress(find.byType(PetInteraction));
    });
  });
}
