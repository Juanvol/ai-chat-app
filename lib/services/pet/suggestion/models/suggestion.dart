// Flutter 3.24 / Dart 3.5
/// 建议层级（与 D8 设计一致）
enum SuggestionLevel {
  /// L1: 闲聊气泡，~16 tok，定时触发
  l1,

  /// L2: 场景感知，~64 tok，需要上下文
  l2,

  /// L3: 深度建议，~256 tok，需要画像+记忆
  l3,

  /// L4: 主动提醒/总结，~128 tok，定点触发
  l4;

  /// 预估 token 消耗（decision + chat）
  int get estimatedTokens => switch (this) {
    SuggestionLevel.l1 => 96,
    SuggestionLevel.l2 => 200,
    SuggestionLevel.l3 => 500,
    SuggestionLevel.l4 => 300,
  };

  /// 是否仅气泡（不弹聊天框）
  bool get isBubbleOnly => this == SuggestionLevel.l1 || this == SuggestionLevel.l2;
}

/// 一次主动建议
class Suggestion {
  final SuggestionLevel level;
  final String text;
  final String topic;
  final String source; // 上下文来源标注，如 "日记"、"时段"、"记忆"
  final DateTime createdAt;

  Suggestion({
    required this.level,
    required this.text,
    this.topic = '',
    this.source = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 外壳气泡文本（带来源标注，L2+ 显示为什么说这句话）
  String toBubbleText() {
    if (source.isNotEmpty && level != SuggestionLevel.l1) {
      return '$text （来源：$source）';
    }
    return text;
  }

  Map<String, dynamic> toJson() => {
    'level': level.name,
    'text': text,
    'topic': topic,
    'source': source,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Suggestion.fromJson(Map<String, dynamic> json) => Suggestion(
    level: SuggestionLevel.values.firstWhere(
      (e) => e.name == json['level'],
      orElse: () => SuggestionLevel.l1,
    ),
    text: json['text'] as String? ?? '',
    topic: json['topic'] as String? ?? '',
    source: json['source'] as String? ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}
