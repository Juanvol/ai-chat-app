// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/services/pet/suggestion/models/suggestion.dart';

void main() {
  group('SuggestionLevel', () {
    test('estimatedTokens 合理', () {
      expect(SuggestionLevel.l1.estimatedTokens, lessThan(SuggestionLevel.l2.estimatedTokens));
      expect(SuggestionLevel.l3.estimatedTokens, greaterThan(SuggestionLevel.l2.estimatedTokens));
    });

    test('isBubbleOnly', () {
      expect(SuggestionLevel.l1.isBubbleOnly, isTrue);
      expect(SuggestionLevel.l2.isBubbleOnly, isTrue);
      expect(SuggestionLevel.l3.isBubbleOnly, isFalse);
      expect(SuggestionLevel.l4.isBubbleOnly, isFalse);
    });
  });

  group('Suggestion', () {
    test('toJson/fromJson 往返一致', () {
      final s = Suggestion(
        level: SuggestionLevel.l2,
        text: '记得休息喵~',
        topic: '健康提醒',
        source: '时段+日记',
      );
      final json = s.toJson();
      final restored = Suggestion.fromJson(json);
      expect(restored.level, SuggestionLevel.l2);
      expect(restored.text, '记得休息喵~');
      expect(restored.topic, '健康提醒');
      expect(restored.source, '时段+日记');
    });

    test('toBubbleText L1 不带来源标注', () {
      final s = Suggestion(
        level: SuggestionLevel.l1,
        text: '早上好喵~ ☀️',
        source: '时段',
      );
      expect(s.toBubbleText(), '早上好喵~ ☀️');
    });

    test('toBubbleText L2+ 带来源标注', () {
      final s = Suggestion(
        level: SuggestionLevel.l2,
        text: '记得休息喵~',
        source: '时段+日记',
      );
      expect(s.toBubbleText(), contains('来源：时段+日记'));
    });

    test('fromJson 缺字段用默认值', () {
      final s = Suggestion.fromJson({});
      expect(s.level, SuggestionLevel.l1);
      expect(s.text, '');
      expect(s.topic, '');
      expect(s.source, '');
    });
  });
}
