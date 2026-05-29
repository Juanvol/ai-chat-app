// Flutter 3.24 / Dart 3.5
class TokenUsage {
  final String id;
  final String conversationId;
  final String modelId;
  final String providerId;
  final int promptTokens;
  final int completionTokens;
  final DateTime createdAt;

  TokenUsage({
    required this.id,
    required this.conversationId,
    required this.modelId,
    required this.providerId,
    required this.promptTokens,
    required this.completionTokens,
    required this.createdAt,
  });

  int get totalTokens => promptTokens + completionTokens;

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'modelId': modelId,
        'providerId': providerId,
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TokenUsage.fromJson(Map<String, dynamic> j) => TokenUsage(
        id: j['id'] as String,
        conversationId: j['conversationId'] as String,
        modelId: j['modelId'] as String,
        providerId: j['providerId'] as String,
        promptTokens: (j['promptTokens'] as num).toInt(),
        completionTokens: (j['completionTokens'] as num).toInt(),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
