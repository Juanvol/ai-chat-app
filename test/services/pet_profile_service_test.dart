// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:deepseek_chat/services/pet/pet_profile_service.dart';
import 'package:deepseek_chat/models/pet_profile.dart';

void main() {
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('pet_profile_test_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
  });

  group('PetProfileService', () {
    test('loadProfile 无数据返回默认', () async {
      final svc = PetProfileService();
      final profile = await svc.loadProfile();
      expect(profile.nickname, isEmpty);
      expect(profile.growthStage, GrowthStage.newbie);
    });

    test('saveProfile/loadProfile 往返', () async {
      final svc = PetProfileService();
      final original = PetProfile(nickname: '小明', interests: ['编程']);
      await svc.saveProfile(original);
      final loaded = await svc.loadProfile();
      expect(loaded.nickname, '小明');
      expect(loaded.interests, ['编程']);
    });

    test('recordRejection 累加被拒计数', () async {
      final svc = PetProfileService();
      await svc.recordRejection('suggestion');
      await svc.recordRejection('suggestion');
      await svc.recordRejection('chat');
      final profile = await svc.loadProfile();
      expect(profile.rejections['suggestion'], 2);
      expect(profile.rejections['chat'], 1);
    });

    test('incrementInteractions 递增并更新成长阶段', () async {
      final svc = PetProfileService();
      await svc.incrementInteractions(30);
      final profile = await svc.loadProfile();
      expect(profile.interactionCount, 30);
      expect(profile.growthStage, GrowthStage.familiar);
    });

    test('getRejectionProbability 被拒多次后降低概率', () async {
      final svc = PetProfileService();
      for (int i = 0; i < 5; i++) {
        await svc.recordRejection('suggestion');
      }
      final prob = await svc.getRejectionProbability('suggestion');
      expect(prob, lessThan(0.7));
    });
  });
}
