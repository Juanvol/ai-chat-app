// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import '../../lib/pet/pet_memory.dart';

void main() {
  group('PetMemory', () {
    test('默认值正确', () {
      final memory = PetMemory(
        content: '用户在备课',
        context: 'screenshot_browser',
      );
      expect(memory.content, '用户在备课');
      expect(memory.context, 'screenshot_browser');
      expect(memory.affectionGain, 0);
    });

    test('toJson 和 fromJson 往返一致', () {
      final original = PetMemory(
        id: 'test-id-123',
        content: '用户经常在晚上备课',
        context: 'screenshot_browser',
        affectionGain: 15,
      );
      final json = original.toJson();
      final restored = PetMemory.fromJson(json);
      expect(restored.id, 'test-id-123');
      expect(restored.content, '用户经常在晚上备课');
      expect(restored.context, 'screenshot_browser');
      expect(restored.affectionGain, 15);
    });

    test('id 为空时自动生成', () {
      final memory = PetMemory(content: 'test');
      expect(memory.id, isNotEmpty);
    });

    test('createdAt 默认值为构造时间', () {
      final before = DateTime.now();
      final memory = PetMemory(content: 'test');
      final after = DateTime.now();
      expect(memory.createdAt.isAfter(before) || memory.createdAt == before, true);
      expect(memory.createdAt.isBefore(after) || memory.createdAt == after, true);
    });
  });
}
