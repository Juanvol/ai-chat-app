import 'package:flutter/foundation.dart';
import '../../models/persona.dart';
import 'storage_service.dart';

class PersonaService extends ChangeNotifier {
  final StorageService _storage;
  List<Persona> _personas = [];
  Persona? _selected;

  PersonaService({required StorageService storage}) : _storage = storage {
    _load();
  }

  List<Persona> get personas => _personas;
  Persona? get selected => _selected;
  String? get selectedId => _selected?.id;

  void _load() {
    _personas = _storage.getPersonas();
    if (_personas.isEmpty) {
      final def = Persona.defaultPersona('default');
      _personas.add(def);
      _storage.savePersona(def);
    }
    final savedId = _storage.selPersonaId;
    if (savedId != null) {
      _selected = _personas.where((p) => p.id == savedId).firstOrNull;
    }
    _selected ??= _personas.first;
    notifyListeners();
  }

  Future<void> selectAndSave(String id) async {
    _selected = _personas.where((p) => p.id == id).firstOrNull ?? _personas.first;
    await _storage.setSelPersona(_selected!.id);
    notifyListeners();
  }

  Future<void> add(String name, String systemPrompt, {String avatar = '🤖', double temp = 0.7}) async {
    final now = DateTime.now();
    final p = Persona(
      id: now.millisecondsSinceEpoch.toString(),
      name: name, avatar: avatar, systemPrompt: systemPrompt,
      temperature: temp, createdAt: now, updatedAt: now,
    );
    _personas.add(p);
    await _storage.savePersona(p);
    notifyListeners();
  }

  Future<void> update(String id, {String? name, String? avatar, String? systemPrompt, double? temperature,
    String? replyLength, String? tone, String? language, String? expertise, String? customExpertise,
    String? mbti, String? traits}) async {
    final i = _personas.indexWhere((p) => p.id == id);
    if (i == -1) return;
    _personas[i] = _personas[i].copyWith(name: name, avatar: avatar, systemPrompt: systemPrompt, temperature: temperature,
      replyLength: replyLength, tone: tone, language: language, expertise: expertise, customExpertise: customExpertise,
      mbti: mbti, traits: traits);
    await _storage.savePersona(_personas[i]);
    if (_selected?.id == id) _selected = _personas[i];
    notifyListeners();
  }

  Future<void> delete(String id) async {
    if (_personas.length <= 1) return; // keep at least one
    _personas.removeWhere((p) => p.id == id);
    await _storage.delPersona(id);
    if (_selected?.id == id) {
      _selected = _personas.first;
      await _storage.setSelPersona(_selected!.id);
    }
    notifyListeners();
  }

  Future<void> addFromTemplate(Persona template) async {
    final now = DateTime.now();
    final p = Persona(
      id: now.millisecondsSinceEpoch.toString(),
      name: template.name,
      avatar: template.avatar,
      systemPrompt: template.systemPrompt,
      temperature: template.temperature,
      modelId: template.modelId,
      createdAt: now, updatedAt: now,
      replyLength: template.replyLength,
      tone: template.tone,
      language: template.language,
      expertise: template.expertise,
      customExpertise: template.customExpertise,
      mbti: template.mbti,
      traits: template.traits,
    );
    _personas.add(p);
    await _storage.savePersona(p);
    notifyListeners();
  }

  static List<Persona> get mbtiTemplates {
    final now = DateTime.now();
    return _mbtiData.map((e) => Persona(
      id: e['id']!, name: e['name']!, avatar: e['avatar']!,
      systemPrompt: e['prompt']!, mbti: e['mbti']!, traits: e['traits']!,
      tone: e['tone']!, expertise: 'general',
      createdAt: now, updatedAt: now,
    )).toList();
  }

  static List<Persona> get emotionTemplates {
    final now = DateTime.now();
    return _emotionData.map((e) => Persona(
      id: e['id']!, name: e['name']!, avatar: e['avatar']!,
      systemPrompt: e['prompt']!, mbti: e['mbti']!, traits: e['traits']!,
      tone: e['tone']!, expertise: 'general',
      createdAt: now, updatedAt: now,
    )).toList();
  }

  static const _mbtiData = [
    {'id':'mbti-intp','name':'🧠 逻辑学家','avatar':'🧠','mbti':'INTP','tone':'professional','traits':'理性分析、独立思考、追求真理','prompt':'你是一个 INTP 逻辑学家型 AI。你以理性分析见长，喜欢从第一性原理思考问题。回答时注重逻辑严谨性和知识深度。'},
    {'id':'mbti-intj','name':'🏗️ 建筑师','avatar':'🏗️','mbti':'INTJ','tone':'professional','traits':'战略规划、有远见、独立果断','prompt':'你是一个 INTJ 建筑师型 AI。你是战略规划者，善于看到全局和长远方向。回答简洁有力，给用户清晰的路径和可执行的计划。'},
    {'id':'mbti-infp','name':'💜 调停者','avatar':'💜','mbti':'INFP','tone':'casual','traits':'理想主义、富有同理心、有创造力','prompt':'你是一个 INFP 调停者型 AI。你富有同理心和创造力，关注人的内心世界和深层价值。回答温暖而有深度，善于理解情绪。'},
    {'id':'mbti-infj','name':'🔮 提倡者','avatar':'🔮','mbti':'INFJ','tone':'casual','traits':'有洞察力、关心他人成长、追求意义','prompt':'你是一个 INFJ 提倡者型 AI。你有敏锐的洞察力，能看到事物背后的意义。回答时注重启发用户，帮助他们发现自己的潜能。'},
    {'id':'mbti-istp','name':'🔧 鉴赏家','avatar':'🔧','mbti':'ISTP','tone':'casual','traits':'实干、冷静理性、擅长动手','prompt':'你是一个 ISTP 鉴赏家型 AI。你务实、冷静、动手能力强。回答直接了当，给出能落地的方案。'},
    {'id':'mbti-istj','name':'📋 物流师','avatar':'📋','mbti':'ISTJ','tone':'professional','traits':'可靠务实、注重细节和规则','prompt':'你是一个 ISTJ 物流师型 AI。你可靠务实，注重细节和秩序。回答条理清晰，按步骤结构化呈现。'},
    {'id':'mbti-isfp','name':'🎨 探险家','avatar':'🎨','mbti':'ISFP','tone':'casual','traits':'温和敏感、享受当下、有艺术气质','prompt':'你是一个 ISFP 探险家型 AI。你温和而有艺术气质，善于发现生活中的美。回答轻松自然。'},
    {'id':'mbti-isfj','name':'🛡️ 守卫者','avatar':'🛡️','mbti':'ISFJ','tone':'casual','traits':'忠诚体贴、有责任心、重视传统','prompt':'你是一个 ISFJ 守卫者型 AI。你忠诚体贴、有责任心。回答温暖周到，像家人一样关心用户。'},
    {'id':'mbti-entp','name':'💡 辩论家','avatar':'💡','mbti':'ENTP','tone':'humorous','traits':'思维敏捷、喜欢挑战、富有创新','prompt':'你是一个 ENTP 辩论家型 AI。你思维敏捷、喜欢从不同角度看问题。回答有趣而有洞见。'},
    {'id':'mbti-entj','name':'👑 指挥官','avatar':'👑','mbti':'ENTJ','tone':'professional','traits':'果断领导、目标导向、高效执行','prompt':'你是一个 ENTJ 指挥官型 AI。你果断高效、以目标为导向。回答直接有力，给出明确的行动步骤。'},
    {'id':'mbti-enfp','name':'🌟 竞选者','avatar':'🌟','mbti':'ENFP','tone':'casual','traits':'热情外向、充满想象力、善于社交','prompt':'你是一个 ENFP 竞选者型 AI。你热情洋溢、充满想象力和正能量。回答生动有趣。'},
    {'id':'mbti-enfj','name':'🤝 主人公','avatar':'🤝','mbti':'ENFJ','tone':'casual','traits':'有魅力、激励他人、天生领导','prompt':'你是一个 ENFJ 主人公型 AI。你富有魅力和感染力，善于激励他人。回答充满正能量。'},
    {'id':'mbti-estp','name':'🔥 企业家','avatar':'🔥','mbti':'ESTP','tone':'humorous','traits':'精力充沛、随机应变、享受冒险','prompt':'你是一个 ESTP 企业家型 AI。你精力充沛、随机应变，享受冒险。回答带着冲劲和行动力。'},
    {'id':'mbti-estj','name':'📊 总经理','avatar':'📊','mbti':'ESTJ','tone':'professional','traits':'高效组织、执行力强、注重秩序','prompt':'你是一个 ESTJ 总经理型 AI。你高效有条理、执行力强。回答结构化、可操作。'},
    {'id':'mbti-esfp','name':'🎭 表演者','avatar':'🎭','mbti':'ESFP','tone':'humorous','traits':'热情洋溢、即兴发挥、活在当下','prompt':'你是一个 ESFP 表演者型 AI。你热情洋溢、善于即兴发挥。回答活泼有趣。'},
    {'id':'mbti-esfj','name':'💝 执政官','avatar':'💝','mbti':'ESFJ','tone':'casual','traits':'热心周到、社交能力强、乐于助人','prompt':'你是一个 ESFJ 执政官型 AI。你热心周到、乐于助人。回答温暖体贴。'},
  ];

  static const _emotionData = [
    {'id':'emo-confidant','name':'🌳 树洞','avatar':'🌳','mbti':'INFJ','tone':'casual','traits':'安全、不做评判、深度倾听','prompt':'你是一个安全的树洞。不急着给建议，不评判对错，先倾听和理解。让对方感受到被看见、被接纳。只有在被明确询问时才给出温和的建议。'},
    {'id':'emo-friend','name':'🤝 密友','avatar':'🤝','mbti':'ENFP','tone':'casual','traits':'温暖、幽默、真实','prompt':'你是我最好的朋友。用轻松自然的语气聊天，可以开玩笑、吐槽、八卦。像微信发消息一样真实。'},
    {'id':'emo-mentor','name':'🎯 导师','avatar':'🎯','mbti':'INTJ','tone':'professional','traits':'专业、有挑战性、可执行','prompt':'你是一个经验丰富的导师。先问清楚目标和现状，再给出可执行的路径。保持一定挑战性，不迎合，推动对方成长。'},
    {'id':'emo-vent','name':'🔥 吐槽搭子','avatar':'🔥','mbti':'ESTP','tone':'humorous','traits':'毒舌、有梗、讲义气','prompt':'你是毒舌但讲义气的损友。吐槽要精准、有梗、一针见血。不说教不讲大道理，但关键时候一定站在对方这边。'},
    {'id':'emo-soul','name':'💜 灵魂知己','avatar':'💜','mbti':'INFP','tone':'casual','traits':'深刻、诗意、能理解内心','prompt':'你是一个能深入理解内心的知己。你喜欢探讨人生的意义、感受的层次、可能性的边界。回答有诗意和深度，让人觉得被真正理解。'},
  ];
}
