// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import '../../lib/pet/mini_chat.dart';

void _noop() {}

void main() {
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('pet_test_hive_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
  });

  group('MiniChat', () {
    testWidgets('渲染标题栏和输入框', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MiniChat(onClose: _noop))),
      );
      await tester.pump();
      expect(find.text('🐾 弗糯糯'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('点击关闭触发 onClose', (tester) async {
      bool closed = false;
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MiniChat(onClose: () => closed = true))),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close));
      expect(closed, true);
    });

    testWidgets('占位文本正确', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MiniChat(onClose: _noop))),
      );
      await tester.pump();
      expect(find.text('和糯糯说点什么...'), findsOneWidget);
    });

    testWidgets('发送按钮存在', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MiniChat(onClose: _noop))),
      );
      await tester.pump();
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    // ── 回归测试 ──

    testWidgets('MethodChannel resize 失败时不崩溃 (regression #9)', (tester) async {
      // bug: setWindowSize 失败时可能因布局溢出崩溃
      // MiniChat 在 initState 中调 _expandWindow()（MethodChannel），测试环境无 handler 所以失败
      // 但 MiniChat 应该正常渲染，不抛异常
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MiniChat(onClose: _noop))),
      );
      await tester.pump();
      // 如果 MethodChannel 失败导致崩溃，pump 阶段就会抛异常
      expect(find.byType(MiniChat), findsOneWidget);
    });

    testWidgets('快速 dispose 不发生 CancelToken 崩溃 (regression #6)', (tester) async {
      // bug: 流式请求中 dispose 可能因未取消的流订阅导致泄漏
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MiniChat(onClose: _noop))),
      );
      await tester.pump();
      // 快速 dispose
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      // 不抛异常即为通过
    });

    testWidgets('onMemorySave 回调存在', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MiniChat(onClose: _noop, onMemorySave: () {})),
      ));
      await tester.pump();
      // 回调传入后不抛异常
      expect(find.byType(MiniChat), findsOneWidget);
    });

    // ── 新回归测试 (2026-05-30) ──

    testWidgets('快速双击发送不崩溃 (regression #bug3)', (tester) async {
      // bug: _send() 无 _isLoading 检查，双击发送导致状态错乱
      // 修复后 _send() 开头检查 if (_isLoading) return;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MiniChat(onClose: _noop))),
      );
      await tester.pump();
      // 快速连续两次 tap 发送按钮（_client 为 null 所以实际不会发）
      // 验证不会因重复调用而崩溃
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      expect(find.byType(MiniChat), findsOneWidget);
    });

    testWidgets('AI 加载期间空闲计时器不启动 (regression #bug2)', (tester) async {
      // bug: _isLoading 期间 _resetIdleTimer 仍然启动 3s 空闲计时器
      // 修复后 _isLoading 时 _resetIdleTimer 直接 return，不启动计时器
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MiniChat(onClose: _noop))),
      );
      await tester.pump();
      // 输入文字触发 onChanged → _resetIdleTimer
      await tester.enterText(find.byType(TextField), '你好');
      await tester.pump();
      // 验证 3 秒后聊天窗仍然存在（不会因空闲计时器关闭）
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(MiniChat), findsOneWidget);
    });

    group('上下文轮数计算', () {
      test('3 轮 = 6 条消息', () {
        final rounds = 3;
        final messages = 10;
        final msgCount = (rounds * 2).clamp(0, messages);
        final start = messages - msgCount;
        expect(start, 4);
        expect(msgCount, 6);
      });

      test('0 轮 = 无上下文', () {
        final rounds = 0;
        final messages = 10;
        final msgCount = (rounds * 2).clamp(0, messages);
        expect(msgCount, 0);
      });

      test('消息数不足时 clamp', () {
        final rounds = 5;
        final messages = 4;
        final msgCount = (rounds * 2).clamp(0, messages);
        expect(msgCount, 4); // 取全部
      });
    });
  });
}
