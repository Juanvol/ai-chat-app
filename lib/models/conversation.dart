import 'message.dart';

class Conversation {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  List<Message> messages;
  String modelId;
  bool isPinned;

  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.modelId = 'deepseek-v4-pro',
    this.isPinned = false,
  });

  int get messageCount => messages.where((m) => !m.isStreaming).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'modelId': modelId,
        'isPinned': isPinned,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        modelId: json['modelId'] as String? ?? 'deepseek-v4-pro',
        isPinned: json['isPinned'] as bool? ?? false,
        messages: (json['messages'] as List<dynamic>)
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
