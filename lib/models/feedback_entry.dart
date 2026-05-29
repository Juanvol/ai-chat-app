class FeedbackEntry {
  final String id;
  final String conversationId;
  final String userMessage;
  final String aiResponse;
  String reason;
  final DateTime createdAt;
  bool processed;
  String? adjustmentResult;

  FeedbackEntry({
    required this.id,
    required this.conversationId,
    required this.userMessage,
    required this.aiResponse,
    this.reason = '不满意',
    required this.createdAt,
    this.processed = false,
    this.adjustmentResult,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'userMessage': userMessage,
        'aiResponse': aiResponse,
        'reason': reason,
        'createdAt': createdAt.toIso8601String(),
        'processed': processed,
        'adjustmentResult': adjustmentResult,
      };

  factory FeedbackEntry.fromJson(Map<String, dynamic> j) => FeedbackEntry(
        id: j['id'] as String,
        conversationId: j['conversationId'] as String,
        userMessage: j['userMessage'] as String,
        aiResponse: j['aiResponse'] as String,
        reason: j['reason'] as String? ?? '不满意',
        createdAt: DateTime.parse(j['createdAt'] as String),
        processed: j['processed'] as bool? ?? false,
        adjustmentResult: j['adjustmentResult'] as String?,
      );
}
