import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/models/model_config.dart';

void main() {
  group('宠物模型过滤逻辑', () {
    test('主模型列表排除 custom-model 和 mimo-v2-omni', () {
      final mainModels = ModelConfig.builtIn
          .where((m) => m.id != 'custom-model' && m.id != 'mimo-v2-omni')
          .toList();
      expect(mainModels.any((m) => m.id == 'custom-model'), isFalse);
      expect(mainModels.any((m) => m.id == 'mimo-v2-omni'), isFalse);
      expect(mainModels.any((m) => m.id == 'ds-chat'), isTrue);
    });

    test('视觉模型列表包含 xiaomi 和 gpt-4o', () {
      final visionModels = ModelConfig.builtIn
          .where((m) => m.providerId == 'xiaomi' || m.id == 'gpt-4o')
          .toList();
      expect(visionModels.any((m) => m.id == 'mimo-v2-omni'), isTrue);
      expect(visionModels.any((m) => m.id == 'gpt-4o'), isTrue);
    });
  });
}
