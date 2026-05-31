// Flutter 3.24 / Dart 3.5
import 'package:hive/hive.dart';
import '../pet/pet_state.dart';
import '../pet/pet_config.dart';

class PetService {
  static const _stateBoxName = 'pet_state';
  static const _configBoxName = 'pet_config';

  // ── 宠物状态读写 ──

  static Future<PetState> loadState() async {
    final box = await Hive.openBox(_stateBoxName);
    final raw = box.get('state');
    if (raw == null) return PetState();
    return PetState.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  static Future<void> saveState(PetState state) async {
    final box = await Hive.openBox(_stateBoxName);
    await box.put('state', state.toJson());
  }

  // ── 宠物配置读写 ──

  static Future<PetConfig> loadConfig() async {
    final box = await Hive.openBox(_configBoxName);
    final raw = box.get('config');
    if (raw == null) return PetConfig();
    return PetConfig.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  static Future<void> saveConfig(PetConfig config) async {
    final box = await Hive.openBox(_configBoxName);
    await box.put('config', config.toJson());
  }

  // ── 配置变更监听（供引擎 #2 使用） ──

  static Future<Stream<BoxEvent>> watchConfig() async {
    final box = await Hive.openBox(_configBoxName);
    return box.watch();
  }

  static Future<Stream<BoxEvent>> watchState() async {
    final box = await Hive.openBox(_stateBoxName);
    return box.watch();
  }

  // ── 宠物开关控制 ──

  static Future<void> enablePet() async {
    final config = await loadConfig();
    await saveConfig(config.copyWith(enabled: true));
  }

  static Future<void> disablePet() async {
    final config = await loadConfig();
    await saveConfig(config.copyWith(enabled: false));
  }

  static Future<bool> isPetEnabled() async {
    final config = await loadConfig();
    return config.enabled;
  }
}
