// Flutter 3.24 / Dart 3.5
class PetMemory {
  static int _idCounter = 0;
  static final String _sessionPrefix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  final String id;
  final String content;
  final String context;
  final DateTime createdAt;
  final int affectionGain;

  PetMemory({
    String? id,
    required this.content,
    this.context = '',
    DateTime? createdAt,
    this.affectionGain = 0,
  })  : id = id ?? '${_sessionPrefix}_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}',
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'context': context,
    'createdAt': createdAt.toIso8601String(),
    'affectionGain': affectionGain,
  };

  factory PetMemory.fromJson(Map<String, dynamic> json) {
    return PetMemory(
      id: json['id'] as String?,
      content: json['content'] as String? ?? '',
      context: json['context'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      affectionGain: (json['affectionGain'] as num?)?.toInt() ?? 0,
    );
  }
}
