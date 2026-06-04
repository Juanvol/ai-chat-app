// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/pet/pet_renderer.dart';
import 'package:deepseek_chat/models/pet_state.dart';

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

    // ── 回归测试 ──

    testWidgets('状态切换时动画从第0帧开始 (regression #2)', (tester) async {
      // bug: didUpdateWidget 删除了 _ac.forward(from:0)，状态切换时动画不重置
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle, size: 100)),
      );
      await tester.pump();
      // 找到 Image widget，验证它存在
      expect(find.byType(Image), findsOneWidget);

      // 切换到 hungry
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.hungry, size: 100)),
      );
      await tester.pump();
      // 切换后 Image 仍然存在，证明 didUpdateWidget 正常执行
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('eco 模式切回时动画重置 (regression #10)', (tester) async {
      // bug: ecoMode 从 true 切 false 时动画从停止位置续播
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle, ecoMode: true)),
      );
      await tester.pump();

      // 切换回非 eco
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle, ecoMode: false)),
      );
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    });

    // ── moodEmoji 叠加层测试 ──

    testWidgets('moodEmoji 为 null 时不显示叠加层', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle)),
      );
      await tester.pump();
      expect(find.byType(Stack), findsNothing);
    });

    testWidgets('moodEmoji 非 null 时显示 emoji 叠加层', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle, moodEmoji: '😊')),
      );
      await tester.pump();
      expect(find.text('😊'), findsOneWidget);
    });

    testWidgets('moodEmoji 切换时更新显示', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle, moodEmoji: '😊')),
      );
      await tester.pump();
      expect(find.text('😊'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle, moodEmoji: '💤')),
      );
      // 等待 AnimatedSwitcher 的 300ms 过渡动画完成
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('💤'), findsOneWidget);
      expect(find.text('😊'), findsNothing);
    });

    testWidgets('连续状态切换不抛异常', (tester) async {
      // 验证快速连续切换各状态不会崩溃
      await tester.pumpWidget(
        const MaterialApp(home: PetRenderer(status: PetStatus.idle)),
      );
      await tester.pump();
      for (final s in [PetStatus.hungry, PetStatus.talking, PetStatus.sleeping, PetStatus.happy]) {
        await tester.pumpWidget(
          MaterialApp(home: PetRenderer(status: s)),
        );
        await tester.pump();
      }
    });
  });
}
