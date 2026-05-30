// Flutter 3.24 / Dart 3.5
class PetPersona {
  final String name;
  final String systemPrompt;
  final String? templateId;
  final String traits;

  static const _defaultPrompt =
      '你是弗糯糯，一只可爱的虚拟宠物精灵。'
      '性格：软萌、粘人、偶尔丧丧的摆烂。'
      '自称"糯糯"，句尾加"喵~"或"..."。'
      '保持短小可爱，不超过2句话。';

  PetPersona({
    this.name = '弗糯糯',
    this.systemPrompt = _defaultPrompt,
    this.templateId,
    this.traits = '',
  });

  PetPersona copyWith({
    String? name,
    String? systemPrompt,
    String? templateId,
    String? traits,
  }) {
    return PetPersona(
      name: name ?? this.name,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      templateId: templateId ?? this.templateId,
      traits: traits ?? this.traits,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'systemPrompt': systemPrompt,
    if (templateId != null) 'templateId': templateId,
    'traits': traits,
  };

  factory PetPersona.fromJson(Map<String, dynamic> json) {
    return PetPersona(
      name: json['name'] as String? ?? '弗糯糯',
      systemPrompt: json['systemPrompt'] as String? ?? _defaultPrompt,
      templateId: json['templateId'] as String?,
      traits: json['traits'] as String? ?? '',
    );
  }
}
