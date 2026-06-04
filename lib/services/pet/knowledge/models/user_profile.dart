// Flutter 3.24 / Dart 3.5

class UserProfile {
  final String name;
  final List<String> interests;
  final Map<String, double> habitWeights;
  final List<String> recentTopics;
  final DateTime updatedAt;

  UserProfile({
    this.name = '',
    List<String>? interests,
    Map<String, double>? habitWeights,
    List<String>? recentTopics,
    DateTime? updatedAt,
  })  : interests = List.from(interests ?? []),
        habitWeights = Map.from(habitWeights ?? {}),
        recentTopics = List.from(recentTopics ?? []),
        updatedAt = updatedAt ?? DateTime.now();

  UserProfile copyWith({
    String? name,
    List<String>? interests,
    Map<String, double>? habitWeights,
    List<String>? recentTopics,
    DateTime? updatedAt,
  }) =>
      UserProfile(
        name: name ?? this.name,
        interests: interests ?? List.from(this.interests),
        habitWeights: habitWeights ?? Map.from(this.habitWeights),
        recentTopics: recentTopics ?? List.from(this.recentTopics),
        updatedAt: updatedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        if (name.isNotEmpty) 'name': name,
        'interests': interests,
        'habitWeights': habitWeights,
        'recentTopics': recentTopics,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String? ?? '',
      interests: (json['interests'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      habitWeights: (json['habitWeights'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
          {},
      recentTopics: (json['recentTopics'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      updatedAt:
          DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime.now(),
    );
  }

  @override
  String toString() =>
      'UserProfile(interests=$interests, habits=${habitWeights.keys}, topics=$recentTopics)';
}
