// Flutter 3.24 / Dart 3.5
enum AiFrequency { silent, occasional, chatty }

enum TriggerScene { browser, document, settings, all }

class PetConfig {
  final bool enabled;
  final AiFrequency aiFrequency;
  final Set<TriggerScene> triggerScenes;
  final int petX;
  final int petY;
  final double petScale;
  final String skinName;
  final bool autoStart;
  final DateTime? quietUntil;

  PetConfig({
    this.enabled = false,
    this.aiFrequency = AiFrequency.occasional,
    Set<TriggerScene>? triggerScenes,
    this.petX = 0,
    this.petY = 200,
    this.petScale = 1.0,
    this.skinName = 'funuonuo',
    this.autoStart = false,
    this.quietUntil,
  }) : triggerScenes = triggerScenes ?? {TriggerScene.all};

  PetConfig copyWith({
    bool? enabled,
    AiFrequency? aiFrequency,
    Set<TriggerScene>? triggerScenes,
    int? petX,
    int? petY,
    double? petScale,
    String? skinName,
    bool? autoStart,
    DateTime? quietUntil,
  }) {
    return PetConfig(
      enabled: enabled ?? this.enabled,
      aiFrequency: aiFrequency ?? this.aiFrequency,
      triggerScenes: triggerScenes ?? this.triggerScenes,
      petX: petX ?? this.petX,
      petY: petY ?? this.petY,
      petScale: (petScale ?? this.petScale).clamp(0.5, 1.5),
      skinName: skinName ?? this.skinName,
      autoStart: autoStart ?? this.autoStart,
      quietUntil: quietUntil ?? this.quietUntil,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'aiFrequency': aiFrequency.name,
    'triggerScenes': triggerScenes.map((e) => e.name).toList(),
    'petX': petX,
    'petY': petY,
    'petScale': petScale,
    'skinName': skinName,
    'autoStart': autoStart,
    if (quietUntil != null) 'quietUntil': quietUntil!.toIso8601String(),
  };

  factory PetConfig.fromJson(Map<String, dynamic> json) {
    Set<TriggerScene> parseScenes(dynamic scenes) {
      if (scenes is! List || scenes.isEmpty) return {TriggerScene.all};
      final result = scenes
          .map((e) {
            try {
              return TriggerScene.values.firstWhere((v) => v.name == e.toString());
            } catch (_) {
              return null;
            }
          })
          .whereType<TriggerScene>()
          .toSet();
      return result.isEmpty ? {TriggerScene.all} : result;
    }

    return PetConfig(
      enabled: json['enabled'] == true,
      aiFrequency: AiFrequency.values.firstWhere(
        (e) => e.name == json['aiFrequency'],
        orElse: () => AiFrequency.occasional,
      ),
      triggerScenes: parseScenes(json['triggerScenes']),
      petX: (json['petX'] as num?)?.toInt() ?? 0,
      petY: (json['petY'] as num?)?.toInt() ?? 200,
      petScale: (json['petScale'] as num?)?.toDouble() ?? 1.0,
      skinName: json['skinName'] as String? ?? 'funuonuo',
      autoStart: json['autoStart'] == true,
      quietUntil: json['quietUntil'] != null
          ? DateTime.tryParse(json['quietUntil'] as String)
          : null,
    );
  }
}
