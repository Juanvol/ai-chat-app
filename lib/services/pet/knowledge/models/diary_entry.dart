// Flutter 3.24 / Dart 3.5

enum DiaryEntryType { event, highlight, summary }

class DiaryEntry {
  final String id;
  final DiaryEntryType type;
  final String content;
  final String mood;
  final String? sourceType; // feed/pet/tap/talk/suggestion/...
  final DateTime date;
  final DateTime? dateKey; // 归日键 (yyyy-MM-dd)，null 则按 date

  DiaryEntry({
    required this.id,
    required this.type,
    required this.content,
    this.mood = '📝',
    this.sourceType,
    required this.date,
    DateTime? dateKey,
  }) : dateKey = dateKey ?? DateTime(date.year, date.month, date.day);

  DiaryEntry copyWith({
    String? id,
    DiaryEntryType? type,
    String? content,
    String? mood,
    String? sourceType,
    DateTime? date,
    DateTime? dateKey,
  }) =>
      DiaryEntry(
        id: id ?? this.id,
        type: type ?? this.type,
        content: content ?? this.content,
        mood: mood ?? this.mood,
        sourceType: sourceType ?? this.sourceType,
        date: date ?? this.date,
        dateKey: dateKey ?? this.dateKey,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'content': content,
        'mood': mood,
        if (sourceType != null) 'sourceType': sourceType,
        'date': date.toIso8601String(),
        'dateKey': dateKey!.toIso8601String().substring(0, 10),
      };

  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'event';
    final type = DiaryEntryType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => DiaryEntryType.event,
    );
    return DiaryEntry(
      id: json['id'] as String,
      type: type,
      content: json['content'] as String? ?? '',
      mood: json['mood'] as String? ?? '📝',
      sourceType: json['sourceType'] as String?,
      date: DateTime.tryParse('${json['date'] ?? ''}') ?? DateTime.now(),
      dateKey: json['dateKey'] != null
          ? DateTime.tryParse('${json['dateKey']} 00:00:00')
          : null,
    );
  }

  @override
  String toString() =>
      'DiaryEntry(id=$id, type=${type.name}, content=$content, date=$date)';
}
