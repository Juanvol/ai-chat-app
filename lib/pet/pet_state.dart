// Flutter 3.24 / Dart 3.5
enum PetStatus { idle, hungry, eating, happy, sleepy, sleeping, talking }

class PetState {
  final int hunger;
  final double mood;
  final int energy;
  final int affection;
  final PetStatus status;
  final DateTime lastFed;
  final int totalInteractions;

  PetState({
    this.hunger = 100,
    this.mood = 100,
    this.energy = 100,
    this.affection = 0,
    this.status = PetStatus.idle,
    DateTime? lastFed,
    this.totalInteractions = 0,
  }) : lastFed = lastFed ?? DateTime.now();

  PetState copyWith({
    int? hunger,
    double? mood,
    int? energy,
    int? affection,
    PetStatus? status,
    DateTime? lastFed,
    int? totalInteractions,
  }) {
    return PetState(
      hunger: (hunger ?? this.hunger).clamp(0, 100),
      mood: (mood ?? this.mood).clamp(0, 100),
      energy: (energy ?? this.energy).clamp(0, 100),
      affection: (affection ?? this.affection).clamp(0, 999999),
      status: status ?? this.status,
      lastFed: lastFed ?? this.lastFed,
      totalInteractions: (totalInteractions ?? this.totalInteractions).clamp(0, 999999),
    );
  }

  Map<String, dynamic> toJson() => {
    'hunger': hunger,
    'mood': mood,
    'energy': energy,
    'affection': affection,
    'status': status.name,
    'lastFed': lastFed.toIso8601String(),
    'totalInteractions': totalInteractions,
  };

  factory PetState.fromJson(Map<String, dynamic> json) {
    return PetState(
      hunger: (json['hunger'] as num?)?.toInt() ?? 100,
      mood: (json['mood'] as num?)?.toDouble() ?? 100,
      energy: (json['energy'] as num?)?.toInt() ?? 100,
      affection: (json['affection'] as num?)?.toInt() ?? 0,
      status: PetStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => PetStatus.idle,
      ),
      lastFed: json['lastFed'] != null
          ? DateTime.tryParse(json['lastFed'] as String) ?? DateTime.now()
          : DateTime.now(),
      totalInteractions: (json['totalInteractions'] as num?)?.toInt() ?? 0,
    );
  }
}
