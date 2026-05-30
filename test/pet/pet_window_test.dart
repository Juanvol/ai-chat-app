// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/pet/pet_renderer.dart';
import '../../lib/pet/pet_state.dart';

void main() {
  group('PetRenderer size', () {
    testWidgets('默认 size 为 120', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle)),
      );
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.width, 120);
      expect(image.height, 120);
    });

    testWidgets('接收自定义 size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle, size: 180)),
      );
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.width, 180);
      expect(image.height, 180);
    });

    testWidgets('petScale 0.5 → size 60', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle, size: 60)),
      );
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.width, 60);
      expect(image.height, 60);
    });

    testWidgets('petScale 1.5 → size 180', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle, size: 180)),
      );
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.width, 180);
      expect(image.height, 180);
    });
  });
}
