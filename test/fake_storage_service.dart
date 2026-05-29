// Flutter 3.24 / Dart 3.5
import 'package:deepseek_chat/services/storage_service.dart';
import 'package:deepseek_chat/models/conversation.dart';
import 'package:deepseek_chat/models/memory.dart';
import 'package:deepseek_chat/models/persona.dart';
import 'package:deepseek_chat/models/feedback_entry.dart';
import 'package:deepseek_chat/models/token_usage.dart';

/// 内存版 StorageService — 测试用，不依赖 Hive。
class FakeStorageService extends StorageService {
  final Map<String, dynamic> _settings = {};
  final Map<String, Map<String, dynamic>> _convRaw = {};
  final Map<String, Memory> _mems = {};
  final Map<String, Persona> _personas = {};
  final Map<String, FeedbackEntry> _fbs = {};
  final List<TokenUsage> _usages = [];

  String? _apiKey;
  String _selModel = 'ds-v4-pro';
  String? _selPersonaId;
  String? _adjText;

  void injectKey(String k) => _apiKey = k;
  void injectModel(String m) => _selModel = m;
  void injectPersona(String? id) => _selPersonaId = id;
  void injectAdjText(String t) => _adjText = t;
  void injectSetting(String key, dynamic v) => _settings[key] = v;

  void injectConv(Conversation c) {
    _convRaw[c.id] = c.toJson();
  }

  @override
  Future<void> save(String key, dynamic v) async => _settings[key] = v;

  @override
  dynamic get(String key, [dynamic def]) => _settings[key] ?? def;

  @override
  String? get apiKey => _apiKey ?? _settings['api_key'];
  @override
  Future<void> setApiKey(String k) async => _apiKey = k;

  @override
  String get selModel => _selModel;
  @override
  Future<void> setSelModel(String m) async => _selModel = m;

  @override
  String? get selPersonaId => _selPersonaId;
  @override
  Future<void> setSelPersona(String? id) async => _selPersonaId = id;

  @override
  String? get adjText => _adjText;
  @override
  Future<void> setAdjText(String t) async => _adjText = t;

  @override
  List<Conversation> getConvs() {
    final list = _convRaw.values
        .map((j) => Conversation.fromJson(Map<String, dynamic>.from(j)))
        .toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<void> saveConv(Conversation c, {bool flush = true}) async {
    _convRaw[c.id] = c.toJson();
  }

  @override
  Future<void> delConv(String id) async => _convRaw.remove(id);

  @override
  Future<void> saveMem(Memory m) async => _mems[m.id] = m;
  @override
  Memory? getMem(String id) => _mems[id];
  @override
  List<Memory> getMems() => _mems.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  @override
  Future<void> delMem(String id) async => _mems.remove(id);

  @override
  Future<void> savePersona(Persona p) async => _personas[p.id] = p;
  @override
  Persona? getPersona(String id) => _personas[id];
  @override
  List<Persona> getPersonas() => _personas.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  @override
  Future<void> delPersona(String id) async => _personas.remove(id);

  @override
  Future<void> saveFb(FeedbackEntry f) async => _fbs[f.id] = f;
  @override
  List<FeedbackEntry> getFbs() => _fbs.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  @override
  List<FeedbackEntry> getUnprocessedFbs() =>
      _fbs.values.where((f) => !f.processed).toList();
  @override
  Future<void> delFb(String id) async => _fbs.remove(id);

  @override
  Future<void> saveUsage(TokenUsage u) async => _usages.add(u);

  @override
  List<TokenUsage> getUsages() => List.unmodifiable(_usages);
}
