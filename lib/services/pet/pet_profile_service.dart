// Flutter 3.24 / Dart 3.5
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../models/pet_profile.dart';

class PetProfileService extends ChangeNotifier {
  static const _boxName = 'pet_profile';
  static const _key = 'profile';

  Future<Box> get _box => Hive.openBox(_boxName);

  Future<PetProfile> loadProfile() async {
    try {
      final box = await _box;
      final raw = box.get(_key);
      if (raw == null) return PetProfile();
      return PetProfile.fromJson(Map<String, dynamic>.from(raw as Map));
    } catch (_) {
      return PetProfile();
    }
  }

  Future<void> saveProfile(PetProfile profile) async {
    try {
      final box = await _box;
      await box.put(_key, profile.toJson());
      notifyListeners();
    } catch (e) {
      debugPrint('PetProfileService.saveProfile failed: $e');
    }
  }

  Future<void> recordRejection(String scene) async {
    final profile = await loadProfile();
    final rejections = Map<String, int>.from(profile.rejections);
    rejections[scene] = (rejections[scene] ?? 0) + 1;
    await saveProfile(profile.copyWith(rejections: rejections));
  }

  Future<void> incrementInteractions(int count) async {
    final profile = await loadProfile();
    final newCount = profile.interactionCount + count;
    await saveProfile(profile.copyWith(interactionCount: newCount));
  }

  Future<double> getRejectionProbability(String scene) async {
    final profile = await loadProfile();
    final rejectCount = profile.rejections[scene] ?? 0;
    return (0.7 - rejectCount * 0.05).clamp(0.2, 0.7);
  }
}
