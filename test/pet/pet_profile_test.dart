// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/models/pet_profile.dart';

void main() {
  group('PetProfile', () {
    test('默认值', () {
      final p = PetProfile();
      expect(p.nickname, isEmpty);
      expect(p.interests, isEmpty);
      expect(p.callMe, isEmpty);
      expect(p.interactionCount, 0);
      expect(p.growthStage, GrowthStage.newbie);
    });

    test('toJson/fromJson 往返', () {
      final p = PetProfile(
        nickname: '小明',
        interests: ['编程', '游戏'],
        callMe: '小明',
        interactionCount: 50,
        growthStage: GrowthStage.familiar,
        rejections: {'suggestion': 3},
      );
      final json = p.toJson();
      final restored = PetProfile.fromJson(json);
      expect(restored.nickname, '小明');
      expect(restored.interests, ['编程', '游戏']);
      expect(restored.interactionCount, 50);
      expect(restored.growthStage, GrowthStage.familiar);
      expect(restored.rejections['suggestion'], 3);
    });

    test('fromJson 缺字段默认值', () {
      final p = PetProfile.fromJson({});
      expect(p.nickname, isEmpty);
      expect(p.growthStage, GrowthStage.newbie);
    });

    test('GrowthStage 按轮数计算', () {
      expect(GrowthStageExt.fromInteractions(0), GrowthStage.newbie);
      expect(GrowthStageExt.fromInteractions(15), GrowthStage.newbie);
      expect(GrowthStageExt.fromInteractions(30), GrowthStage.familiar);
      expect(GrowthStageExt.fromInteractions(200), GrowthStage.close);
      expect(GrowthStageExt.fromInteractions(1000), GrowthStage.oldFriend);
    });

    test('copyWith', () {
      final p = PetProfile(nickname: '旧');
      final updated = p.copyWith(nickname: '新', interactionCount: 10);
      expect(updated.nickname, '新');
      expect(updated.interactionCount, 10);
    });
  });
}
