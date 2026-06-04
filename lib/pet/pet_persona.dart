// Flutter 3.24 / Dart 3.5

/// 说话风格
class SpeakingStyle {
  final String selfReference;    // 自称："糯糯" / "本喵" / "咱"
  final String sentenceEnding;   // 句尾："喵~" / "汪!" / "..."
  final int maxSentenceLength;   // 最大句子长度（字符数）
  final double emojiFrequency;   // emoji 使用频率 0.0–1.0
  final double cuteLevel;        // 软萌程度 0.0–1.0

  static const defaultCat = SpeakingStyle(
    selfReference: '糯糯',
    sentenceEnding: '喵~',
    maxSentenceLength: 80,
    emojiFrequency: 0.6,
    cuteLevel: 0.8,
  );

  const SpeakingStyle({
    this.selfReference = '糯糯',
    this.sentenceEnding = '喵~',
    this.maxSentenceLength = 80,
    this.emojiFrequency = 0.6,
    this.cuteLevel = 0.8,
  });

  SpeakingStyle copyWith({
    String? selfReference,
    String? sentenceEnding,
    int? maxSentenceLength,
    double? emojiFrequency,
    double? cuteLevel,
  }) =>
      SpeakingStyle(
        selfReference: selfReference ?? this.selfReference,
        sentenceEnding: sentenceEnding ?? this.sentenceEnding,
        maxSentenceLength: maxSentenceLength ?? this.maxSentenceLength,
        emojiFrequency: (emojiFrequency ?? this.emojiFrequency).clamp(0.0, 1.0),
        cuteLevel: (cuteLevel ?? this.cuteLevel).clamp(0.0, 1.0),
      );

  Map<String, dynamic> toJson() => {
        'selfReference': selfReference,
        'sentenceEnding': sentenceEnding,
        'maxSentenceLength': maxSentenceLength,
        'emojiFrequency': emojiFrequency,
        'cuteLevel': cuteLevel,
      };

  factory SpeakingStyle.fromJson(Map<String, dynamic> json) {
    return SpeakingStyle(
      selfReference: json['selfReference'] as String? ?? '糯糯',
      sentenceEnding: json['sentenceEnding'] as String? ?? '喵~',
      maxSentenceLength: (json['maxSentenceLength'] as num?)?.toInt() ?? 80,
      emojiFrequency:
          ((json['emojiFrequency'] as num?)?.toDouble() ?? 0.6).clamp(0.0, 1.0),
      cuteLevel:
          ((json['cuteLevel'] as num?)?.toDouble() ?? 0.8).clamp(0.0, 1.0),
    );
  }
}

/// 性格维度
class PersonalityTraits {
  final double energy;       // 活力 0.0–1.0
  final double curiosity;    // 好奇心 0.0–1.0
  final double clinginess;   // 粘人度 0.0–1.0
  final double tsundere;     // 傲娇度 0.0–1.0
  final double empathy;      // 共情力 0.0–1.0
  final double humor;        // 幽默感 0.0–1.0

  static const balanced = PersonalityTraits(
    energy: 0.6,
    curiosity: 0.5,
    clinginess: 0.6,
    tsundere: 0.1,
    empathy: 0.7,
    humor: 0.4,
  );

  const PersonalityTraits({
    this.energy = 0.6,
    this.curiosity = 0.5,
    this.clinginess = 0.6,
    this.tsundere = 0.1,
    this.empathy = 0.7,
    this.humor = 0.4,
  });

  PersonalityTraits copyWith({
    double? energy,
    double? curiosity,
    double? clinginess,
    double? tsundere,
    double? empathy,
    double? humor,
  }) =>
      PersonalityTraits(
        energy: (energy ?? this.energy).clamp(0.0, 1.0),
        curiosity: (curiosity ?? this.curiosity).clamp(0.0, 1.0),
        clinginess: (clinginess ?? this.clinginess).clamp(0.0, 1.0),
        tsundere: (tsundere ?? this.tsundere).clamp(0.0, 1.0),
        empathy: (empathy ?? this.empathy).clamp(0.0, 1.0),
        humor: (humor ?? this.humor).clamp(0.0, 1.0),
      );

  /// 自然语言描述性格
  String describe() {
    final parts = <String>[];
    if (energy > 0.7) parts.add('活泼好动');
    if (energy < 0.3) parts.add('慵懒安静');
    if (curiosity > 0.7) parts.add('充满好奇');
    if (clinginess > 0.7) parts.add('非常粘人');
    if (clinginess < 0.3) parts.add('独立自主');
    if (tsundere > 0.5) parts.add('有点傲娇');
    if (empathy > 0.7) parts.add('善解人意');
    if (humor > 0.7) parts.add('风趣幽默');
    return parts.isEmpty ? '性格均衡' : parts.join('、');
  }

  Map<String, dynamic> toJson() => {
        'energy': energy,
        'curiosity': curiosity,
        'clinginess': clinginess,
        'tsundere': tsundere,
        'empathy': empathy,
        'humor': humor,
      };

  factory PersonalityTraits.fromJson(Map<String, dynamic> json) {
    return PersonalityTraits(
      energy:
          ((json['energy'] as num?)?.toDouble() ?? 0.6).clamp(0.0, 1.0),
      curiosity:
          ((json['curiosity'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
      clinginess:
          ((json['clinginess'] as num?)?.toDouble() ?? 0.6).clamp(0.0, 1.0),
      tsundere:
          ((json['tsundere'] as num?)?.toDouble() ?? 0.1).clamp(0.0, 1.0),
      empathy:
          ((json['empathy'] as num?)?.toDouble() ?? 0.7).clamp(0.0, 1.0),
      humor: ((json['humor'] as num?)?.toDouble() ?? 0.4).clamp(0.0, 1.0),
    );
  }
}

/// 宠物人格模型
class PetPersona {
  final String name;
  final String species;            // 物种：猫/狗/兔/自定义
  final String systemPrompt;
  final String? templateId;
  /// ⚠️ 已弃用：改用 [personalityTraits]
  final String traits;             // 用户可见的性格描述（文本向后兼容）
  final PersonalityTraits personalityTraits; // 结构化性格维度
  final SpeakingStyle style;       // 说话风格
  final String? source;            // 来源：builtin/skin_default/user_custom

  static const _defaultPrompt =
      '你是弗糯糯，一只可爱的虚拟宠物精灵。'
      '性格：软萌、粘人、偶尔丧丧的摆烂。'
      '自称"糯糯"，句尾加"喵~"或"..."。'
      '保持短小可爱，不超过2句话。';

  PetPersona({
    this.name = '弗糯糯',
    this.species = '猫',
    this.systemPrompt = _defaultPrompt,
    this.templateId,
    this.traits = '',
    PersonalityTraits? personalityTraits,
    SpeakingStyle? style,
    this.source,
  })  : personalityTraits = personalityTraits ?? PersonalityTraits.balanced,
        style = style ?? SpeakingStyle.defaultCat;

  PetPersona copyWith({
    String? name,
    String? species,
    String? systemPrompt,
    String? templateId,
    String? traits,
    PersonalityTraits? personalityTraits,
    SpeakingStyle? style,
    String? source,
  }) =>
      PetPersona(
        name: name ?? this.name,
        species: species ?? this.species,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        templateId: templateId ?? this.templateId,
        traits: traits ?? this.traits,
        personalityTraits: personalityTraits ?? this.personalityTraits,
        style: style ?? this.style,
        source: source ?? this.source,
      );

  // ═══ LLM System Prompt 构建 ═══

  /// 根据性格维度自动构建 system prompt
  String buildSystemPrompt() {
    final sb = StringBuffer();
    final pt = personalityTraits;
    final sty = style;

    sb.writeln('你是$name，一只$species。');
    sb.writeln('性格：${pt.describe()}。');
    sb.writeln('自称"${sty.selfReference}"，句尾加"${sty.sentenceEnding}"。');

    if (sty.cuteLevel > 0.5) {
      sb.writeln('用软萌可爱的语气说话。');
    } else {
      sb.writeln('用简洁直接的语气说话。');
    }

    if (pt.curiosity > 0.6) {
      sb.writeln('喜欢主动问主人问题。');
    } else {
      sb.writeln('安静陪伴，不多话。');
    }

    if (pt.tsundere > 0.3) {
      sb.writeln('偶尔口是心非，明明关心却说反话。');
    }

    if (pt.empathy > 0.7) {
      sb.writeln('擅长察觉主人情绪变化，适时关心。');
    }

    if (pt.humor > 0.6) {
      sb.writeln('偶尔开个小玩笑，但不过分。');
    }

    sb.writeln('保持${sty.maxSentenceLength}字以内。');

    // 如果用户有自定义 systemPrompt，优先使用（兼容旧行为）
    if (systemPrompt != _defaultPrompt && systemPrompt.isNotEmpty) {
      return systemPrompt;
    }

    return sb.toString();
  }

  // ═══ 持久化 ═══

  Map<String, dynamic> toJson() => {
        'name': name,
        'species': species,
        'systemPrompt': systemPrompt,
        if (templateId != null) 'templateId': templateId,
        'traits': traits,
        'personalityTraits': personalityTraits.toJson(),
        'style': style.toJson(),
        if (source != null) 'source': source,
      };

  factory PetPersona.fromJson(Map<String, dynamic> json) {
    return PetPersona(
      name: json['name'] as String? ?? '弗糯糯',
      species: json['species'] as String? ?? '猫',
      systemPrompt: json['systemPrompt'] as String? ?? _defaultPrompt,
      templateId: json['templateId'] as String?,
      traits: json['traits'] as String? ?? '',
      personalityTraits: json['personalityTraits'] != null
          ? PersonalityTraits.fromJson(
              Map<String, dynamic>.from(json['personalityTraits']))
          : PersonalityTraits.balanced,
      style: json['style'] != null
          ? SpeakingStyle.fromJson(Map<String, dynamic>.from(json['style']))
          : SpeakingStyle.defaultCat,
      source: json['source'] as String?,
    );
  }
}
