// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/pet/pet_config.dart';

void main() {
  group('AiFrequency', () {
    test('枚举值数量为 3', () {
      expect(AiFrequency.values.length, 3);
    });

    test('name 与枚举小写一致', () {
      expect(AiFrequency.silent.name, 'silent');
      expect(AiFrequency.occasional.name, 'occasional');
      expect(AiFrequency.chatty.name, 'chatty');
    });
  });

  group('TriggerScene', () {
    test('枚举值数量为 4', () {
      expect(TriggerScene.values.length, 4);
    });

    test('name 与枚举小写一致', () {
      expect(TriggerScene.browser.name, 'browser');
      expect(TriggerScene.document.name, 'document');
      expect(TriggerScene.settings.name, 'settings');
      expect(TriggerScene.all.name, 'all');
    });
  });

  group('PetConfig', () {
    test('默认值正确', () {
      final config = PetConfig();
      expect(config.enabled, false);
      expect(config.aiFrequency, AiFrequency.occasional);
      expect(config.triggerScenes, {TriggerScene.all});
      expect(config.petScale, 1.0);
      expect(config.skinName, 'funuonuo');
      expect(config.autoStart, false);
      expect(config.quietUntil, isNull);
    });

    test('toJson 和 fromJson 往返一致', () {
      final original = PetConfig(
        enabled: true,
        aiFrequency: AiFrequency.chatty,
        triggerScenes: {TriggerScene.browser, TriggerScene.document},
        petX: 100,
        petY: 200,
        petScale: 0.8,
        skinName: 'custom_01',
        autoStart: true,
      );
      final json = original.toJson();
      final restored = PetConfig.fromJson(json);
      expect(restored.enabled, true);
      expect(restored.aiFrequency, AiFrequency.chatty);
      expect(restored.triggerScenes, {TriggerScene.browser, TriggerScene.document});
      expect(restored.petX, 100);
      expect(restored.petY, 200);
      expect(restored.petScale, 0.8);
      expect(restored.skinName, 'custom_01');
      expect(restored.autoStart, true);
    });

    test('fromJson 处理旧格式（无 triggerScenes 字段）', () {
      final json = {
        'enabled': true,
        'aiFrequency': 'silent',
        'petX': 50,
        'petY': 100,
        'petScale': 1.2,
        'skinName': 'funuonuo',
        'autoStart': false,
      };
      final config = PetConfig.fromJson(json);
      expect(config.triggerScenes, {TriggerScene.all});
    });

    test('fromJson 处理空 triggerScenes 列表', () {
      final json = {
        'triggerScenes': <String>[],
      };
      final config = PetConfig.fromJson(json);
      expect(config.triggerScenes, {TriggerScene.all});
    });

    test('quietUntil 序列化和反序列化正确', () {
      final now = DateTime.now();
      final original = PetConfig(quietUntil: now);
      final json = original.toJson();
      final restored = PetConfig.fromJson(json);
      expect(restored.quietUntil?.millisecondsSinceEpoch,
          closeTo(now.millisecondsSinceEpoch, 1000));
    });

    test('copyWith 部分更新', () {
      final config = PetConfig(petX: 100, petY: 200);
      final updated = config.copyWith(petX: 300);
      expect(updated.petX, 300);
      expect(updated.petY, 200);
      expect(updated.enabled, false);
    });

    test('petScale clamp 到 0.5-1.5', () {
      final low = PetConfig().copyWith(petScale: 0.1);
      final high = PetConfig().copyWith(petScale: 3.0);
      expect(low.petScale, 0.5);
      expect(high.petScale, 1.5);
    });

    test('构造函数也 clamp petScale', () {
      final low = PetConfig(petScale: 0.01);
      final high = PetConfig(petScale: 5.0);
      expect(low.petScale, 0.5);
      expect(high.petScale, 1.5);
    });

    test('fromJson 也 clamp petScale', () {
      final low = PetConfig.fromJson({'petScale': 0.01});
      final high = PetConfig.fromJson({'petScale': 5.0});
      expect(low.petScale, 0.5);
      expect(high.petScale, 1.5);
    });
  });
}
