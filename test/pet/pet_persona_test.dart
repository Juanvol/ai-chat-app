// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/pet/pet_persona.dart';

void main() {
  group('PetPersona', () {
    test('默认值正确', () {
      final p = PetPersona();
      expect(p.name, '弗糯糯');
      expect(p.species, '猫');
      expect(p.systemPrompt, isNotEmpty);
      expect(p.templateId, isNull);
      expect(p.traits, isEmpty);
      expect(p.style.selfReference, '糯糯');
      expect(p.style.cuteLevel, 0.8);
      expect(p.personalityTraits.energy, 0.6);
      expect(p.source, isNull);
    });

    test('toJson/fromJson 往返一致', () {
      final p = PetPersona(
        name: '测试喵',
        species: '猫',
        systemPrompt: '你是一只高冷的猫',
        templateId: 'tsundere_cat',
        traits: '傲娇,毒舌',
        personalityTraits: PersonalityTraits(tsundere: 0.9, energy: 0.3),
        style: SpeakingStyle(sentenceEnding: '哼~', cuteLevel: 0.2),
        source: 'builtin',
      );
      final json = p.toJson();
      final restored = PetPersona.fromJson(json);
      expect(restored.name, '测试喵');
      expect(restored.species, '猫');
      expect(restored.systemPrompt, '你是一只高冷的猫');
      expect(restored.templateId, 'tsundere_cat');
      expect(restored.traits, '傲娇,毒舌');
      expect(restored.personalityTraits.tsundere, 0.9);
      expect(restored.personalityTraits.energy, 0.3);
      expect(restored.style.sentenceEnding, '哼~');
      expect(restored.style.cuteLevel, 0.2);
      expect(restored.source, 'builtin');
    });

    test('fromJson 缺字段时用默认值', () {
      final p = PetPersona.fromJson({});
      expect(p.name, '弗糯糯');
      expect(p.species, '猫');
      expect(p.personalityTraits.energy, 0.6);
      expect(p.style.selfReference, '糯糯');
    });

    test('copyWith 部分更新', () {
      final p = PetPersona(name: '旧名', traits: '粘人');
      final updated = p.copyWith(name: '新名');
      expect(updated.name, '新名');
      expect(updated.traits, '粘人');
    });

    test('buildSystemPrompt 包含性格描述', () {
      final p = PetPersona(
        name: '小傲',
        species: '猫',
        personalityTraits: PersonalityTraits(tsundere: 0.8, empathy: 0.8, curiosity: 0.7),
      );
      final prompt = p.buildSystemPrompt();
      expect(prompt, contains('小傲'));
      expect(prompt, contains('猫'));
      expect(prompt, contains('傲娇'));
      expect(prompt, contains('善解人意'));
      expect(prompt, contains('喜欢主动问主人问题'));
    });

    test('buildSystemPrompt 自定义 systemPrompt 优先', () {
      final p = PetPersona(
        systemPrompt: '你是一只来自外星的生物，说地球话很勉强。',
        personalityTraits: PersonalityTraits(energy: 0.1),
      );
      final prompt = p.buildSystemPrompt();
      expect(prompt, contains('来自外星的生物'));
    });
  });

  group('SpeakingStyle', () {
    test('默认值', () {
      final s = SpeakingStyle();
      expect(s.selfReference, '糯糯');
      expect(s.sentenceEnding, '喵~');
      expect(s.maxSentenceLength, 80);
    });

    test('clamp 边界', () {
      final s = SpeakingStyle(emojiFrequency: 2.0, cuteLevel: -0.5);
      expect(s.emojiFrequency, 1.0);
      expect(s.cuteLevel, 0.0);
    });
  });

  group('PersonalityTraits', () {
    test('describe 全部高', () {
      final t = PersonalityTraits(
        energy: 0.9,
        curiosity: 0.9,
        clinginess: 0.9,
        tsundere: 0.8,
        empathy: 0.9,
        humor: 0.9,
      );
      final d = t.describe();
      expect(d, contains('活泼好动'));
      expect(d, contains('非常粘人'));
      expect(d, contains('有点傲娇'));
      expect(d, contains('善解人意'));
      expect(d, contains('风趣幽默'));
    });

    test('describe 全部低', () {
      final t = PersonalityTraits(
        energy: 0.1,
        clinginess: 0.1,
        tsundere: 0.1,
        empathy: 0.1,
        humor: 0.1,
        curiosity: 0.5,
      );
      final d = t.describe();
      expect(d, contains('慵懒安静'));
      expect(d, contains('独立自主'));
    });
  });
}
