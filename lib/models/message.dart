class Message {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final String reasoningContent;
  final DateTime createdAt;
  final bool isStreaming;

  Message({
    required this.id,
    required this.role,
    required this.content,
    this.reasoningContent = '',
    required this.createdAt,
    this.isStreaming = false,
  });

  Message copyWith({
    String? id,
    String? role,
    String? content,
    String? reasoningContent,
    DateTime? createdAt,
    bool? isStreaming,
  }) {
    return Message(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      createdAt: createdAt ?? this.createdAt,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'reasoningContent': reasoningContent,
        'createdAt': createdAt.toIso8601String(),
        'isStreaming': isStreaming,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        role: json['role'] as String,
        content: json['content'] as String,
        reasoningContent: json['reasoningContent'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        isStreaming: json['isStreaming'] as bool? ?? false,
      );
}
