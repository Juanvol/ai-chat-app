// Flutter 3.24 / Dart 3.5

enum MemoryTag { fact, habit, interest, event, reminder }

enum MemorySource { rule, llm }

class MemoryEntry {
  final String id;
  final MemoryTag tag;
  final String content;
  final double importance; // 0.0–1.0
  final int recallCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt; // null = 永不过期
  final MemorySource source;
  final String? sourceDiaryId;
  final String? linkedTo; // Phase C 跨域关联

  MemoryEntry({
    required this.id,
    required this.tag,
    required this.content,
    this.importance = 0.5,
    this.recallCount = 0,
    required this.createdAt,
    DateTime? updatedAt,
    this.expiresAt,
    this.source = MemorySource.rule,
    this.sourceDiaryId,
    this.linkedTo,
  }) : updatedAt = updatedAt ?? createdAt;

  MemoryEntry copyWith({
    String? id,
    MemoryTag? tag,
    String? content,
    double? importance,
    int? recallCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
    MemorySource? source,
    String? sourceDiaryId,
    String? linkedTo,
  }) =>
      MemoryEntry(
        id: id ?? this.id,
        tag: tag ?? this.tag,
        content: content ?? this.content,
        importance: (importance ?? this.importance).clamp(0.0, 1.0),
        recallCount: recallCount ?? this.recallCount,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        expiresAt: expiresAt ?? this.expiresAt,
        source: source ?? this.source,
        sourceDiaryId: sourceDiaryId ?? this.sourceDiaryId,
        linkedTo: linkedTo ?? this.linkedTo,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tag': tag.name,
        'content': content,
        'importance': importance,
        'recallCount': recallCount,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        'source': source.name,
        if (sourceDiaryId != null) 'sourceDiaryId': sourceDiaryId,
        if (linkedTo != null) 'linkedTo': linkedTo,
      };

  factory MemoryEntry.fromJson(Map<String, dynamic> json) {
    final tag = MemoryTag.values.firstWhere(
      (e) => e.name == json['tag'],
      orElse: () => MemoryTag.fact,
    );
    final source = MemorySource.values.firstWhere(
      (e) => e.name == json['source'],
      orElse: () => MemorySource.rule,
    );
    return MemoryEntry(
      id: json['id'] as String,
      tag: tag,
      content: json['content'] as String? ?? '',
      importance: ((json['importance'] as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0),
      recallCount: (json['recallCount'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime.now(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse('${json['expiresAt']}')
          : null,
      source: source,
      sourceDiaryId: json['sourceDiaryId'] as String?,
      linkedTo: json['linkedTo'] as String?,
    );
  }

  @override
  String toString() =>
      'MemoryEntry(id=$id, tag=${tag.name}, content=$content, imp=$importance)';
}
