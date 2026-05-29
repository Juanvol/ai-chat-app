class Memory {
  final String id;
  String content;
  int importance; // 1-5
  final DateTime createdAt;
  DateTime updatedAt;
  List<String> tags;

  Memory({
    required this.id,
    required this.content,
    this.importance = 3,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'importance': importance,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'tags': tags,
      };

  factory Memory.fromJson(Map<String, dynamic> j) => Memory(
        id: j['id'] as String,
        content: j['content'] as String,
        importance: (j['importance'] as num?)?.toInt() ?? 3,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        tags: (j['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      );
}
