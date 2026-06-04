// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:deepseek_chat/services/pet/pet_agent_core.dart';

void main() {
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('pet_agent_test_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
  });
  group('PetAgentCore', () {
    test('初始状态', () {
      final agent = PetAgentCore();
      expect(agent.isActive, false);
      expect(agent.attentionLevel, AttentionLevel.l3);
      expect(agent.mood, isA<AgentMood>());
    });

    test('start/stop 生命周期', () {
      final agent = PetAgentCore();
      agent.start();
      expect(agent.isActive, true);
      agent.stop();
      expect(agent.isActive, false);
    });

    test('setAttentionLevel', () {
      final agent = PetAgentCore();
      agent.setAttentionLevel(AttentionLevel.l1);
      expect(agent.attentionLevel, AttentionLevel.l1);
    });

    test('AgentMood 三维概率在 0~1 范围', () {
      final mood = AgentMood();
      expect(mood.activity, inInclusiveRange(0.0, 1.0));
      expect(mood.sass, inInclusiveRange(0.0, 1.0));
      expect(mood.compliance, inInclusiveRange(0.0, 1.0));
    });

    test('AgentMood.applyNoise 加入扰动', () {
      final mood = AgentMood(activity: 0.5, sass: 0.5, compliance: 0.5);
      final perturbed = mood.applyNoise();
      expect(perturbed.activity != 0.5 || perturbed.sass != 0.5, true);
    });

    test('AttentionLevel 决策间隔', () {
      expect(AttentionLevel.l3.interval.inSeconds, 60);
      expect(AttentionLevel.l2.interval.inSeconds, 120);
      expect(AttentionLevel.l1.interval.inSeconds, 300);
      expect(AttentionLevel.l0.interval.inSeconds, 0);
    });

    test('assessLocally 深夜跳过 LLM', () {
      final agent = PetAgentCore();
      final result = agent.assessLocally(
        hour: 2, hunger: 80, energy: 80, hasRecentChat: false,
      );
      expect(result.shouldSkipLLM, true);
    });

    test('assessLocally 饥饿不跳过 LLM', () {
      final agent = PetAgentCore();
      final result = agent.assessLocally(
        hour: 14, hunger: 20, energy: 80, hasRecentChat: false,
      );
      expect(result.shouldSkipLLM, false);
    });

    test('assessLocally 低体力不跳过 LLM', () {
      final agent = PetAgentCore();
      final result = agent.assessLocally(
        hour: 14, hunger: 80, energy: 15, hasRecentChat: false,
      );
      expect(result.shouldSkipLLM, false);
    });

    test('assessLocally 有对话不跳过', () {
      final agent = PetAgentCore();
      final result = agent.assessLocally(
        hour: 14, hunger: 80, energy: 80, hasRecentChat: true,
      );
      expect(result.shouldSkipLLM, false);
    });

    test('纯规则模式标记', () {
      final agent = PetAgentCore();
      expect(agent.isPureRuleMode, false);
    });
  });

  group('ActionEntry', () {
    test('toJson', () {
      final action = ActionEntry(type: 'bubble', content: '你好喵~');
      final json = action.toJson();
      expect(json['type'], 'bubble');
      expect(json['content'], '你好喵~');
      expect(json['timestamp'], isNotNull);
    });
  });
}
