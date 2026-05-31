// Flutter 3.24 / Dart 3.5
enum GrowthStage { newbie, familiar, close, oldFriend }

extension GrowthStageExt on GrowthStage {
  String get label => switch (this) {
        GrowthStage.newbie => '初识',
        GrowthStage.familiar => '熟悉',
        GrowthStage.close => '默契',
        GrowthStage.oldFriend => '老友',
      };

  static GrowthStage fromInteractions(int count) => switch (count) {
        < 30 => GrowthStage.newbie,
        < 200 => GrowthStage.familiar,
        < 1000 => GrowthStage.close,
        _ => GrowthStage.oldFriend,
      };
}

class PetProfile {
  final String nickname;
  final List<String> interests;
  final String callMe;
  final int interactionCount;
  final GrowthStage growthStage;
  final Map<String, int> rejections;

  PetProfile({
    this.nickname = '',
    List<String>? interests,
    this.callMe = '',
    this.interactionCount = 0,
    GrowthStage? growthStage,
    Map<String, int>? rejections,
  })  : interests = List.from(interests ?? []),
        growthStage =
            growthStage ?? GrowthStageExt.fromInteractions(interactionCount),
        rejections = Map.from(rejections ?? {});

  PetProfile copyWith({
    String? nickname,
    List<String>? interests,
    String? callMe,
    int? interactionCount,
    GrowthStage? growthStage,
    Map<String, int>? rejections,
  }) {
    final count = interactionCount ?? this.interactionCount;
    return PetProfile(
      nickname: nickname ?? this.nickname,
      interests: interests ?? List.from(this.interests),
      callMe: callMe ?? this.callMe,
      interactionCount: count,
      growthStage: growthStage ?? GrowthStageExt.fromInteractions(count),
      rejections: rejections ?? Map.from(this.rejections),
    );
  }

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'interests': interests,
        'callMe': callMe,
        'interactionCount': interactionCount,
        'growthStage': growthStage.name,
        'rejections': rejections,
      };

  factory PetProfile.fromJson(Map<String, dynamic> json) {
    return PetProfile(
      nickname: json['nickname'] as String? ?? '',
      interests: (json['interests'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      callMe: json['callMe'] as String? ?? '',
      interactionCount: (json['interactionCount'] as num?)?.toInt() ?? 0,
      growthStage: GrowthStage.values.firstWhere(
        (e) => e.name == json['growthStage'],
        orElse: () => GrowthStage.newbie,
      ),
      rejections: (json['rejections'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
          {},
    );
  }
}
