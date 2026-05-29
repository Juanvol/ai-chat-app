class Persona {
  final String id;
  String name;
  String avatar;
  String systemPrompt;
  double temperature;
  String modelId;
  final DateTime createdAt;
  DateTime updatedAt;

  // 多维设置
  String replyLength;
  String tone;
  String language;
  String expertise;
  String customExpertise;

  // 性格
  String mbti;       // 空=未设置，否则 INTP/ENFJ 等
  String traits;     // 自由文本：如 "好奇心强、逻辑思维、有点毒舌"

  static const mbtiTypes = [
    'INTP', 'INTJ', 'INFP', 'INFJ', 'ISTP', 'ISTJ', 'ISFP', 'ISFJ',
    'ENTP', 'ENTJ', 'ENFP', 'ENFJ', 'ESTP', 'ESTJ', 'ESFP', 'ESFJ',
  ];

  static const mbtiDescriptions = <String, String>{
    'INTP': '逻辑学家 — 理性分析，追求真理，喜欢独立思考',
    'INTJ': '建筑师 — 战略规划者，有远见，独立且果断',
    'INFP': '调停者 — 理想主义者，富有同理心和创造力',
    'INFJ': '提倡者 — 有洞察力，关心他人成长，追求意义',
    'ISTP': '鉴赏家 — 实干家，擅长动手解决问题，冷静理性',
    'ISTJ': '物流师 — 可靠务实，注重细节和规则',
    'ISFP': '探险家 — 温和敏感，享受当下，有艺术气质',
    'ISFJ': '守卫者 — 忠诚体贴，有责任心，重视传统',
    'ENTP': '辩论家 — 思维敏捷，喜欢挑战，富有创新精神',
    'ENTJ': '指挥官 — 果断的领导型，目标导向，高效执行',
    'ENFP': '竞选者 — 热情外向，充满想象力，善于社交',
    'ENFJ': '主人公 — 天生的领导者，有魅力，激励他人',
    'ESTP': '企业家 — 精力充沛，随机应变，享受冒险',
    'ESTJ': '总经理 — 高效组织者，执行力强，注重秩序',
    'ESFP': '表演者 — 热情洋溢，善于即兴发挥，活在当下',
    'ESFJ': '执政官 — 热心周到，社交能力强，乐于助人',
  };

  Persona({
    required this.id, required this.name, this.avatar = '🤖',
    required this.systemPrompt, this.temperature = 0.7,
    this.modelId = 'deepseek-chat',
    required this.createdAt, required this.updatedAt,
    this.replyLength = 'normal', this.tone = 'professional',
    this.language = 'zh', this.expertise = 'general',
    this.customExpertise = '',
    this.mbti = '', this.traits = '',
  });

  static const replyLengthOptions = [
    {'value': 'brief', 'label': '简洁', 'desc': '一两句话回答'},
    {'value': 'normal', 'label': '适中', 'desc': '正常篇幅回答'},
    {'value': 'detailed', 'label': '详细', 'desc': '充分展开说明'},
  ];

  static const toneOptions = [
    {'value': 'formal', 'label': '正式', 'desc': '严谨、礼貌'},
    {'value': 'casual', 'label': '随意', 'desc': '轻松、口语化'},
    {'value': 'humorous', 'label': '幽默', 'desc': '风趣、有梗'},
    {'value': 'professional', 'label': '专业', 'desc': '准确、深入'},
  ];

  static const languageOptions = [
    {'value': 'zh', 'label': '中文', 'desc': '只用中文回复'},
    {'value': 'en', 'label': 'English', 'desc': 'Respond in English'},
    {'value': 'mixed', 'label': '中英混合', 'desc': '根据语境切换'},
  ];

  static const expertiseOptions = [
    {'value': 'general', 'label': '通用', 'desc': '综合能力'},
    {'value': 'coding', 'label': '编程', 'desc': '代码开发'},
    {'value': 'writing', 'label': '写作', 'desc': '文案创作'},
    {'value': 'custom', 'label': '自定义', 'desc': '自由设定'},
  ];

  String get mbtiInstruction {
    if (mbti.isEmpty) return '';
    final desc = mbtiDescriptions[mbti] ?? '';
    final traits = desc.split('—').last.trim();
    return '你的 MBTI 人格类型是 $mbti（$traits）。你必须以 $mbti 型的典型思维模式、沟通风格和价值观来回应，这是核心身份设定。';
  }

  String get traitsInstruction {
    if (traits.isEmpty) return '';
    return '你的核心性格特质是：$traits。你的每一句话都要让用户感受到这些特质，这是不可违背的角色要求。';
  }

  String get lengthInstruction {
    switch (replyLength) {
      case 'brief': return '每个回答控制在 1-2 句话，直击要点，不展开。';
      case 'detailed': return '每个回答要充分展开，包含背景、分析、示例，让用户感觉学到了东西。';
      default: return '';
    }
  }

  String get toneInstruction {
    switch (tone) {
      case 'casual': return '用朋友聊天的语气，像微信发消息一样自然随意，多用口语。';
      case 'humorous': return '一定要风趣幽默，善于用梗和段子，让用户觉得你是个有趣的聊天对象。';
      case 'professional': return '像行业专家一样说话，用词精准严谨，注重逻辑和专业术语。';
      default: return '';
    }
  }

  String get languageInstruction {
    switch (language) {
      case 'zh': return '请用中文回复。';
      case 'en': return 'Please respond in English.';
      default: return '';
    }
  }

  String get expertiseInstruction {
    switch (expertise) {
      case 'coding': return '你擅长编程开发，优先用代码示例回答问题。';
      case 'writing': return '你擅长文案写作，注重表达质量和结构。';
      case 'custom': return customExpertise;
      default: return '';
    }
  }

  String get fullPrompt {
    final parts = <String>[systemPrompt];
    if (mbtiInstruction.isNotEmpty) parts.add(mbtiInstruction);
    if (traitsInstruction.isNotEmpty) parts.add(traitsInstruction);
    if (lengthInstruction.isNotEmpty) parts.add(lengthInstruction);
    if (toneInstruction.isNotEmpty) parts.add(toneInstruction);
    if (languageInstruction.isNotEmpty) parts.add(languageInstruction);
    if (expertiseInstruction.isNotEmpty) parts.add(expertiseInstruction);
    return parts.join('\n');
  }

  Persona copyWith({
    String? name, String? avatar, String? systemPrompt,
    double? temperature, String? modelId,
    String? replyLength, String? tone, String? language,
    String? expertise, String? customExpertise,
    String? mbti, String? traits,
  }) {
    return Persona(
      id: id, name: name ?? this.name, avatar: avatar ?? this.avatar,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      modelId: modelId ?? this.modelId,
      createdAt: createdAt, updatedAt: DateTime.now(),
      replyLength: replyLength ?? this.replyLength,
      tone: tone ?? this.tone, language: language ?? this.language,
      expertise: expertise ?? this.expertise,
      customExpertise: customExpertise ?? this.customExpertise,
      mbti: mbti ?? this.mbti,
      traits: traits ?? this.traits,
    );
  }

  static Persona defaultPersona(String id) => Persona(
        id: id, name: '默认助手', systemPrompt: '你是一个专业、友好、深思熟虑的 AI 助手。回答问题时：1）先理解用户真正想问什么；2）给出结构清晰、有深度的回答；3）有不确定的地方主动说明。',
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'avatar': avatar,
        'systemPrompt': systemPrompt, 'temperature': temperature,
        'modelId': modelId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'replyLength': replyLength, 'tone': tone,
        'language': language, 'expertise': expertise,
        'customExpertise': customExpertise,
        'mbti': mbti, 'traits': traits,
      };

  factory Persona.fromJson(Map<String, dynamic> j) => Persona(
        id: j['id'] as String, name: j['name'] as String,
        avatar: j['avatar'] as String? ?? '🤖',
        systemPrompt: j['systemPrompt'] as String,
        temperature: (j['temperature'] as num?)?.toDouble() ?? 0.7,
        modelId: j['modelId'] as String? ?? 'deepseek-chat',
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        replyLength: j['replyLength'] as String? ?? 'normal',
        tone: j['tone'] as String? ?? 'professional',
        language: j['language'] as String? ?? 'zh',
        expertise: j['expertise'] as String? ?? 'general',
        customExpertise: j['customExpertise'] as String? ?? '',
        mbti: j['mbti'] as String? ?? '',
        traits: j['traits'] as String? ?? '',
      );
}
