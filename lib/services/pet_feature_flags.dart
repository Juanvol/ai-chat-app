// Flutter 3.24 / Dart 3.5
import 'package:hive/hive.dart';

class PetFeatureFlags {
  static const _boxName = 'pet_feature_flags';

  PetFeatureFlags._();

  /// Agent 路由开关：true = MiniChat 通过 Agent 通信，false = 直接调 LLM
  static Future<bool> get agentRouting async {
    try {
      final box = await Hive.openBox(_boxName);
      return box.get('agentRouting', defaultValue: false) as bool;
    } catch (_) {
      return false; // 任何异常 → 降级走旧路径
    }
  }

  static Future<void> setAgentRouting(bool v) async {
    final box = await Hive.openBox(_boxName);
    await box.put('agentRouting', v);
  }
}
