// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/pet/pet_persona.dart';

void main() {
  group('PetPersona', () {
    test('默认值正确', () {
      final p = PetPersona();
      expect(p.name, '弗糯糯');
      expect(p.systemPrompt, isNotEmpty);
      expect(p.templateId, isNull);
      expect(p.traits, isEmpty);
    });

    test('toJson/fromJson 往返一致', () {
      final p = PetPersona(
        name: '测试喵',
        systemPrompt: '你是一只高冷的猫',
        templateId: 'tsundere_cat',
        traits: '傲娇,毒舌',
      );
      final json = p.toJson();
      final restored = PetPersona.fromJson(json);
      expect(restored.name, '测试喵');
      expect(restored.systemPrompt, '你是一只高冷的猫');
      expect(restored.templateId, 'tsundere_cat');
      expect(restored.traits, '傲娇,毒舌');
    });

    test('fromJson 缺字段时用默认值', () {
      final p = PetPersona.fromJson({});
      expect(p.name, '弗糯糯');
    });

    test('copyWith 部分更新', () {
      final p = PetPersona(name: '旧名', traits: '粘人');
      final updated = p.copyWith(name: '新名');
      expect(updated.name, '新名');
      expect(updated.traits, '粘人');
    });
  });
}
