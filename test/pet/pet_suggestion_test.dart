// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/pet/pet_suggestion.dart';

void _noop() {}

void main() {
  group('PetSuggestion', () {
    testWidgets('渲染建议文本和操作按钮', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PetSuggestion(
              text: '主人，你看起来有点累了，休息一下喵~',
              onChat: _noop,
              onDismiss: _noop,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('主人，你看起来有点累了，休息一下喵~'), findsOneWidget);
      expect(find.text('聊聊'), findsOneWidget);
      expect(find.text('忽略'), findsOneWidget);
    });

    testWidgets('点击聊聊触发 onChat', (tester) async {
      bool chatted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PetSuggestion(text: '测试', onChat: () => chatted = true, onDismiss: _noop),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('聊聊'));
      expect(chatted, true);
    });

    testWidgets('点击忽略触发 onDismiss', (tester) async {
      bool dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PetSuggestion(text: '测试', onChat: _noop, onDismiss: () => dismissed = true),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('忽略'));
      expect(dismissed, true);
    });

    testWidgets('点击气泡文本区域触发 onChat', (tester) async {
      bool chatted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PetSuggestion(text: '点我', onChat: () => chatted = true, onDismiss: _noop),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('点我'));
      expect(chatted, true);
    });

    // ── 回归测试 ──

    testWidgets('长文本不溢出，最多显示3行 (regression #bug4)', (tester) async {
      // bug: Text 无 maxLines，AI 长建议导致 UI 溢出
      // 修复后 maxLines: 3, overflow: TextOverflow.ellipsis
      const longText = '这是一段非常长的建议文本用来测试是否会溢出界面'
          '如果没有任何限制这段文本会一直延伸到屏幕外面导致布局出现问题'
          '但是现在我们限制了最多三行所以多余的部分应该被截断显示省略号';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PetSuggestion(text: longText, onChat: _noop, onDismiss: _noop),
          ),
        ),
      );
      await tester.pump();
      // 验证 maxLines 和 overflow 已设置
      final textWidget = tester.widget<Text>(find.text(longText));
      expect(textWidget.maxLines, 3);
      expect(textWidget.overflow, TextOverflow.ellipsis);
    });
  });
}
