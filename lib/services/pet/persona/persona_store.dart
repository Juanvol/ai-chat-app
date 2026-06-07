// Flutter 3.24 / Dart 3.5
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../pet/pet_persona.dart';
import '../pet_logger.dart';

/// 人格持久化服务
///
/// 通过自有 Hive Box 读写 PetPersona。
/// 对齐 DiaryRepoHive / MemoryRepoHive 的模式，不依赖 StorageService。
class PersonaStore extends ChangeNotifier {
  static const _boxName = 'pet_persona';
  Box? _box;
  PetPersona _persona;

  PersonaStore() : _persona = PetPersona();

  PetPersona get persona => _persona;

  /// 当前 system prompt（由 PetPersona.buildSystemPrompt() 生成）
  String get systemPrompt => _persona.buildSystemPrompt();

  // ═══ 初始化 ═══

  Future<void> init() async {
    _box = await _openBox();
    _load();
    PetLogger().trace('PersonaStore', 'init done: ${_persona.name}');
  }

  Future<Box> _openBox() async {
    try {
      return await Hive.openBox(_boxName);
    } catch (e) {
      PetLogger().warn('PersonaStore', 'openBox failed: $e, delete & retry');
      await Hive.deleteBoxFromDisk(_boxName);
      return await Hive.openBox(_boxName);
    }
  }

  // ═══ 读取 ═══

  void _load() {
    if (_box == null) return;
    try {
      final raw = _box!.get('data', defaultValue: '');
      if (raw != null && raw is String && raw.isNotEmpty) {
        _persona = PetPersona.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      }
    } catch (e) {
      PetLogger().warn('PersonaStore', 'load failed, using default: $e');
    }
  }

  // ═══ 保存 ═══

  Future<void> save(PetPersona persona) async {
    _persona = persona;
    await _persist();
    PetLogger().trace('PersonaStore', 'saved: ${_persona.name}');
    notifyListeners();
  }

  // ═══ 便捷更新 ═══

  Future<void> updateTraits(PersonalityTraits traits) async {
    _persona = _persona.copyWith(
      personalityTraits: traits,
      source: 'user_custom',
    );
    await _persist();
    notifyListeners();
    PetLogger().trace('PersonaStore', 'traits updated: ${traits.describe()}');
  }

  Future<void> updateStyle(SpeakingStyle style) async {
    _persona = _persona.copyWith(
      style: style,
      source: 'user_custom',
    );
    await _persist();
    notifyListeners();
    PetLogger().trace('PersonaStore',
        'style updated: ${style.selfReference} ${style.sentenceEnding}');
  }

  Future<void> updateName(String name) async {
    _persona = _persona.copyWith(name: name, source: 'user_custom');
    await _persist();
    notifyListeners();
  }

  /// 直接覆盖（供 pet_settings_screen 等外部调用）
  Future<void> saveOverwrite(PetPersona persona) async {
    _persona = persona;
    await _persist();
    notifyListeners();
    PetLogger().trace('PersonaStore', 'overwrite: ${_persona.name}');
  }

  /// 重置为默认人格
  Future<void> resetToDefault() async {
    _persona = PetPersona();
    await _persist();
    notifyListeners();
    PetLogger().trace('PersonaStore', 'reset to default');
  }

  // ═══ 内部 ═══

  Future<void> _persist() async {
    if (_box == null) return;
    await _box!.put('data', jsonEncode(_persona.toJson()));
  }

  @override
  void dispose() {
    _box = null;
    super.dispose();
  }
}
