import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/conversation.dart';
import '../models/memory.dart';
import '../models/persona.dart';
import '../models/feedback_entry.dart';
import '../models/token_usage.dart';

class StorageService {
  static const _conv = 'conversations';
  static const _settings = 'settings';
  static const _mem = 'memories';
  static const _persona = 'personas';
  static const _fb = 'feedbacks';
  static const _usage = 'token_usage';

  late Box _convBox, _settingsBox, _memBox, _personaBox, _fbBox, _usageBox;
  String? _backupPath;

  Future<void> init() async {
    if (kIsWeb) {
      Hive.init('ai_chat_data');
    } else {
      await Hive.initFlutter();
      try {
        _backupPath = '${(await getApplicationDocumentsDirectory()).path}/conversations.backup.json';
      } catch (_) {}
    }
    _convBox = await _openBoxSafe(_conv);
    _settingsBox = await _openBoxSafe(_settings);
    _memBox = await _openBoxSafe(_mem);
    _personaBox = await _openBoxSafe(_persona);
    _fbBox = await _openBoxSafe(_fb);
    _usageBox = await _openBoxSafe(_usage);
  }

  Future<Box> _openBoxSafe(String name) async {
    Future<void> _cleanLock() async {
      if (kIsWeb) return;
      try {
        final appDir = (await getApplicationDocumentsDirectory()).path;
        final lockFile = File('$appDir/${name}.lock');
        if (lockFile.existsSync()) lockFile.deleteSync();
      } catch (_) {}
    }

    Future<void> _deleteBox() async {
      if (kIsWeb) return;
      try {
        final appDir = (await getApplicationDocumentsDirectory()).path;
        final boxFile = File('$appDir/${name}.hive');
        if (boxFile.existsSync()) boxFile.deleteSync();
        final lockFile = File('$appDir/${name}.lock');
        if (lockFile.existsSync()) lockFile.deleteSync();
      } catch (_) {}
    }

    // 每次尝试前都清锁文件——前一次失败的 openBox 可能留下了新锁
    await _cleanLock();
    try {
      return await Hive.openBox(name);
    } catch (e) {
      await _cleanLock();
      try {
        return await Hive.openBox(name);
      } catch (e2) {
        // 两次都失败 → 文件损坏，删除重建（连锁文件一起删干净）
        await _deleteBox();
        return await Hive.openBox(name);
      }
    }
  }

  Future<void> close() async {
    await Hive.close();
  }

  Future<void> reinitialize() async {
    await close();
    await init();
  }

  // ===== Conversations =====
  Future<void> saveConv(Conversation c, {bool flush = true}) async {
    try {
      await _convBox.put(c.id, c.toJson());
      if (flush) await _convBox.flush();
    } catch (_) {
      // Hive 写入失败不阻塞 JSON 备份
    }
    await _writeJsonBackup(c);
  }

  Future<void> _writeJsonBackup(Conversation c) async {
    if (_backupPath == null) return;
    try {
      final file = File(_backupPath!);
      Map<String, dynamic> backup = {};
      if (await file.exists()) {
        try { backup = jsonDecode(await file.readAsString()) as Map<String, dynamic>; } catch (_) {}
      }
      backup[c.id] = c.toJson();
      // 原子写入：先写临时文件，再 rename，防止杀后台时写一半损坏备份
      final tmp = File('${_backupPath!}.tmp');
      await tmp.writeAsString(jsonEncode(backup), flush: true);
      await tmp.rename(_backupPath!);
    } catch (_) {}
  }
  List<Conversation> getConvs() {
    final result = <Conversation>[];
    final seen = <String>{};
    try {
      for (final j in _convBox.values) {
        try {
          final c = Conversation.fromJson(Map<String, dynamic>.from(j));
          result.add(c);
          seen.add(c.id);
        } catch (_) {
          // 跳过单条损坏数据，不影响其他对话
        }
      }
    } catch (_) {
      // Box 可能因 force-kill 导致文件损坏而打开失败，继续尝试 JSON 备份
    }
    // 始终从 JSON 备份合并——Hive 可能有部分数据未 flush 丢失
    if (_backupPath != null) {
      try {
        final file = File(_backupPath!);
        if (file.existsSync()) {
          final content = file.readAsStringSync();
          if (content.isNotEmpty) {
            final backup = jsonDecode(content) as Map<String, dynamic>;
            for (final entry in backup.entries) {
              if (seen.contains(entry.key)) continue; // Hive 已有，跳过
              try {
                result.add(Conversation.fromJson(Map<String, dynamic>.from(entry.value)));
                try { _convBox.put(entry.key, entry.value); } catch (_) {}
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }
  Future<void> delConv(String id) async {
    await _convBox.delete(id);
    if (_backupPath != null) {
      try {
        final file = File(_backupPath!);
        if (await file.exists()) {
          final backup = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          backup.remove(id);
          // 原子写入
          final tmp = File('${_backupPath!}.tmp');
          await tmp.writeAsString(jsonEncode(backup), flush: true);
          await tmp.rename(_backupPath!);
        }
      } catch (_) {}
    }
  }

  // ===== Memories =====
  Future<void> saveMem(Memory m) => _memBox.put(m.id, m.toJson());
  Memory? getMem(String id) {
    final j = _memBox.get(id); if (j == null) return null;
    return Memory.fromJson(Map<String, dynamic>.from(j));
  }
  List<Memory> getMems() {
    return _memBox.values.map((j) => Memory.fromJson(Map<String, dynamic>.from(j))).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
  Future<void> delMem(String id) => _memBox.delete(id);

  // ===== Scroll Position =====
  Future<void> saveConvScroll(String convId, double offset) =>
      _settingsBox.put('scroll_$convId', offset);
  double getConvScroll(String convId) {
    final v = _settingsBox.get('scroll_$convId');
    return (v is num) ? v.toDouble() : 0.0;
  }

  // ===== Personas =====
  Future<void> savePersona(Persona p) => _personaBox.put(p.id, p.toJson());
  Persona? getPersona(String id) {
    final j = _personaBox.get(id); if (j == null) return null;
    return Persona.fromJson(Map<String, dynamic>.from(j));
  }
  List<Persona> getPersonas() {
    return _personaBox.values.map((j) => Persona.fromJson(Map<String, dynamic>.from(j))).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
  Future<void> delPersona(String id) => _personaBox.delete(id);

  // ===== Feedbacks =====
  Future<void> saveFb(FeedbackEntry f) => _fbBox.put(f.id, f.toJson());
  List<FeedbackEntry> getFbs() {
    return _fbBox.values.map((j) => FeedbackEntry.fromJson(Map<String, dynamic>.from(j))).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  List<FeedbackEntry> getUnprocessedFbs() => getFbs().where((f) => !f.processed).toList();
  Future<void> delFb(String id) => _fbBox.delete(id);

  // ===== Settings =====
  Future<void> save(String key, dynamic v) => _settingsBox.put(key, v);
  dynamic get(String key, [dynamic def]) => _settingsBox.get(key, defaultValue: def);

  String? get apiKey => get('api_key');
  Future<void> setApiKey(String k) => save('api_key', k);

  String get selModel => get('selected_model_id', 'ds-v4-pro');
  Future<void> setSelModel(String m) => save('selected_model_id', m);

  String? get selPersonaId => get('selected_persona_id');
  Future<void> setSelPersona(String id) => save('selected_persona_id', id);

  String? get adjText => get('adjustment_text');
  Future<void> setAdjText(String t) => save('adjustment_text', t);

  // ===== Token Usage =====
  Future<void> saveUsage(TokenUsage u) async => _usageBox.put(u.id, u.toJson());
  List<TokenUsage> getUsages() {
    return _usageBox.values
        .map((j) => TokenUsage.fromJson(Map<String, dynamic>.from(j)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}
