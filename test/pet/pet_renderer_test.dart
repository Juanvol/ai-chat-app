// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/pet/pet_renderer.dart';
import '../../lib/pet/pet_state.dart';

void main() {
  group('PetRenderer', () {
    testWidgets('构建 idle 状态不抛异常', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle)),
      );
      await tester.pump();
      expect(find.byType(PetRenderer), findsOneWidget);
    });

    testWidgets('hungry 状态构建不抛异常', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.hungry)),
      );
      await tester.pump();
      expect(find.byType(PetRenderer), findsOneWidget);
    });

    testWidgets('缺失帧的状态回退到 idle 不抛异常', (tester) async {
      // happy 无独立帧目录，应自动回退到 idle
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.happy)),
      );
      await tester.pump();
      expect(find.byType(PetRenderer), findsOneWidget);
    });

    testWidgets('size 参数生效', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle, size: 200)),
      );
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.width, 200);
      expect(image.height, 200);
    });

    testWidgets('默认 size 为 120', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle)),
      );
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.width, 120);
      expect(image.height, 120);
    });
  });
}
