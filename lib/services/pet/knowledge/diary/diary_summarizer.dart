// Flutter 3.24 / Dart 3.5
import '../../../../api/deepseek_client.dart';
import '../../pet_logger.dart';
import '../models/diary_entry.dart';

class DiarySummarizer {
  final LLMClient _client;
  final String _model;

  DiarySummarizer({LLMClient? client, String model = 'deepseek-v4-pro'})
      : _client = client ?? LLMClient(),
        _model = model;

  /// 生成今日日记总结，返回 null 表示跳过（无事件或预算不足）
  Future<DiaryEntry?> summarize({
    required String dateKey,
    required List<DiaryEntry> todayEvents,
    required int remainingBudget,
    required String personaPrompt,
  }) async {
    // 过滤出今日的事件 + 高亮
    final sourceEvents = todayEvents
        .where((e) => e.type != DiaryEntryType.summary)
        .toList();
    if (sourceEvents.isEmpty) return null;

    // 预算门控：至少需要 100 tok
    if (remainingBudget < 100) {
      PetLogger().trace('DiarySummarizer',
          'skip: remaining budget $remainingBudget < 100');
      return null;
    }

    // 构造事件列表
    final eventLines = sourceEvents.map((e) {
      final time =
          '${e.date.hour.toString().padLeft(2, '0')}:${e.date.minute.toString().padLeft(2, '0')}';
      return '$time ${e.mood} ${e.content}';
    }).join('\n');

    final prompt = '''$personaPrompt

请用第一人称的语气，以"我的日记"为题，写一篇今日总结日记。
今天的事件记录如下：
$eventLines

要求：
- 不超过150字
- 语气软萌、温暖
- 包含今天的心情总结
- 如果有高亮事件，重点提及''';

    try {
      final result = await _client.send(
        history: [],
        userContent: prompt,
        model: _model,
        maxTokens: 256,
        thinkingEnabled: false,
      );

      final content = result.content.trim();
      if (content.isEmpty) return null;

      return DiaryEntry(
        id:
            'summary_${dateKey}_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
        type: DiaryEntryType.summary,
        content: content,
        mood: '📔',
        sourceType: 'summary',
        date: DateTime.now(),
        dateKey: DateTime.tryParse('$dateKey 00:00:00'),
      );
    } catch (e) {
      PetLogger().error('DiarySummarizer', 'LLM call failed', e);
      return null;
    }
  }
}
