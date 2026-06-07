// Flutter 3.24 / Dart 3.5
import 'dart:convert';
import '../../../../api/deepseek_client.dart';
import '../../pet_logger.dart';
import '../models/memory_entry.dart';

class MemoryOrganizer {
  final LLMClient _client;
  final String _model;

  MemoryOrganizer({LLMClient? client, String model = 'deepseek-v4-pro'})
      : _client = client ?? LLMClient(),
        _model = model;

  /// 整理记忆：去重/合并/调整重要性/标记过期
  /// 返回 (更新列表, 删除id列表)
  Future<({List<MemoryEntry> toUpdate, List<String> toDelete})> organize({
    required List<MemoryEntry> existingMemories,
    required int remainingBudget,
  }) async {
    if (existingMemories.isEmpty) return (toUpdate: <MemoryEntry>[], toDelete: <String>[]);

    if (remainingBudget < 150) {
      PetLogger().trace('MemoryOrganizer',
          'skip: remaining budget $remainingBudget < 150');
      return (toUpdate: <MemoryEntry>[], toDelete: <String>[]);
    }

    // 构造输入：每条记忆一行
    final memoryLines = existingMemories
        .where((m) => m.source == MemorySource.rule) // 仅整理规则提取的记忆
        .map((m) =>
            '- [${m.tag.name}] ${m.content} (重要性:${m.importance.toStringAsFixed(1)}, id:${m.id})')
        .join('\n');

    if (memoryLines.isEmpty) return (toUpdate: <MemoryEntry>[], toDelete: <String>[]);

    final prompt = '''你是宠物记忆管理助手。以下是通过规则自动提取的观察片段：

$memoryLines

请分析并输出 JSON：
{
  "toUpdate": [
    {"id": "mem_xxx", "content": "合并后的内容", "tag": "habit", "importance": 0.8}
  ],
  "toDelete": ["mem_yyy"]
}

规则：
1. 相似记忆合并为一条（如"深夜工作"出现多次→合并为一条habit）
2. 重要性调整：常用/重要的标0.7+，边缘信息标0.3以下
3. 过时记忆：如果内容明显不再准确，加入toDelete
4. 仅对规则提取的记忆做操作，不要创造全新记忆''';

    try {
      final result = await _client.send(
        history: [],
        userContent: prompt,
        model: _model,
        maxTokens: 512,
        thinkingEnabled: false,
      );

      final parsed = _parseJson(result.content);
      final toUpdate = (parsed['toUpdate'] as List<dynamic>?)
              ?.map((m) {
                final id = (m as Map)['id'] as String? ?? '';
                final existing =
                    existingMemories.where((e) => e.id == id).firstOrNull;
                if (existing == null) return null;
                return existing.copyWith(
                  content: m['content'] as String?,
                  tag: _parseTag(m['tag'] as String?),
                  importance: (m['importance'] as num?)?.toDouble(),
                  source: MemorySource.llm,
                  updatedAt: DateTime.now(),
                );
              })
              .whereType<MemoryEntry>()
              .toList() ??
          [];
      final toDelete = (parsed['toDelete'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      return (toUpdate: toUpdate, toDelete: toDelete);
    } catch (e) {
      PetLogger().error('MemoryOrganizer', 'LLM call or parse failed', e);
      return (toUpdate: <MemoryEntry>[], toDelete: <String>[]);
    }
  }

  MemoryTag _parseTag(String? tag) {
    return MemoryTag.values.firstWhere(
      (e) => e.name == tag,
      orElse: () => MemoryTag.fact,
    );
  }

  Map<String, dynamic> _parseJson(String text) {
    try {
      // 提取 JSON 块（可能包裹在 markdown 代码块中）
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      final jsonStr = jsonMatch?.group(0) ?? text;
      return Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
    } catch (_) {
      return {};
    }
  }
}
