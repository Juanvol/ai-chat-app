// Flutter 3.24 / Dart 3.5
class PetTokenUsage {
  final DateTime date;
  final int decisionTokens;
  final int chatTokens;
  final int visionTokens;
  final int totalTokens;

  PetTokenUsage({
    DateTime? date,
    this.decisionTokens = 0,
    this.chatTokens = 0,
    this.visionTokens = 0,
    this.totalTokens = 0,
  }) : date = date ?? DateTime.now();

  String get dateKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  PetTokenUsage add({int decision = 0, int chat = 0, int vision = 0}) {
    return PetTokenUsage(
      date: date,
      decisionTokens: decisionTokens + decision,
      chatTokens: chatTokens + chat,
      visionTokens: visionTokens + vision,
      totalTokens: totalTokens + decision + chat + vision,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': dateKey,
    'decisionTokens': decisionTokens,
    'chatTokens': chatTokens,
    'visionTokens': visionTokens,
    'totalTokens': totalTokens,
  };

  factory PetTokenUsage.fromJson(Map<String, dynamic> json) {
    return PetTokenUsage(
      date: json['date'] != null
          ? DateTime.tryParse(json['date'] as String) ?? DateTime.now()
          : DateTime.now(),
      decisionTokens: (json['decisionTokens'] as num?)?.toInt() ?? 0,
      chatTokens: (json['chatTokens'] as num?)?.toInt() ?? 0,
      visionTokens: (json['visionTokens'] as num?)?.toInt() ?? 0,
      totalTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
    );
  }
}
