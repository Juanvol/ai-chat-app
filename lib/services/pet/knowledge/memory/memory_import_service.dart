// Flutter 3.24 / Dart 3.5
import 'dart:convert';
import '../../../../api/deepseek_client.dart';
import '../../pet_logger.dart';
import '../models/memory_entry.dart';
import 'memory_store.dart';

/// 交叉记忆导入服务
///
/// 从主 App 对话中通过 LLM 提取结构化记忆，写入宠物 MemoryStore。
class MemoryImportService {
  final LLMClient _client;
  final String _model;

  MemoryImportService({LLMClient? client, String model = 'deepseek-v4-pro'})
      : _client = client ?? LLMClient(),
        _model = model;

  /// 从对话列表中批量提取记忆
  ///
  /// [conversations] 格式：每项包含 `title` 和 `messages`（[{role, content}]）
  /// 返回成功写入的记忆条目列表
  Future<({List<MemoryEntry> imported, int skipped})> importFromConversations({
    required List<Map<String, dynamic>> conversations,
    required MemoryStore memoryStore,
  }) async {
    if (conversations.isEmpty) {
      return (imported: <MemoryEntry>[], skipped: 0);
    }

    // 按对话逐个提取（每个对话独立 LLM 调用，控制 token 消耗）
    final allImported = <MemoryEntry>[];
    var skipped = 0;

    for (final cov in conversations) {
      final result = await _extractOne(cov);
      if (result == null) {
        skipped++;
        continue;
      }

      // 写入 MemoryStore
      for (final entry in result) {
        await memoryStore.addMemory(entry.content, entry.tag);
        allImported.add(entry);
      }
    }

    PetLogger().info('MemoryImport',
        'imported ${allImported.length} memories from ${conversations.length} conversations, skipped $skipped');
    return (imported: allImported, skipped: skipped);
  }

  /// 从单个对话中提取记忆
  Future<List<MemoryEntry>?> _extractOne(
      Map<String, dynamic> conversation) async {
    final title = conversation['title'] as String? ?? '未知对话';
    final rawMessages = conversation['messages'] as List<dynamic>? ?? [];
    if (rawMessages.isEmpty) return null;

    // 构造对话文本（最多取最近 20 轮，约 4000 字符）
    final messages = rawMessages
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final recent = messages.length > 40
        ? messages.sublist(messages.length - 40)
        : messages;

    final lines = recent.map((m) {
      final role = m['role'] == 'user' ? '用户' : 'AI';
      final content = (m['content'] as String?) ?? '';
      return '$role：$content';
    }).join('\n');

    if (lines.trim().isEmpty) return null;

    final prompt = '''你是一个记忆提取助手。请从以下对话中提取关于用户的**有价值信息**。

对话标题：$title

对话内容：
$lines

请输出 JSON 数组，每条记忆包含 content 和 tag 字段：
- tag 可选值：fact（事实）、habit（习惯）、interest（兴趣）、event（事件）
- content：简短的一句话描述（不超过50字）
- 只提取关于用户的信息，不提取AI说的话
- 如果没有任何值得记录的信息，返回空数组 []

示例输出：
[{"content": "用户最近在看租房信息", "tag": "event"}, {"content": "用户偏好朝阳区、预算3000以内", "tag": "interest"}]

直接输出 JSON 数组，不要包裹在 markdown 代码块中：''';

    try {
      final result = await _client.send(
        history: [],
        userContent: prompt,
        model: _model,
        maxTokens: 512,
        thinkingEnabled: false,
      );

      final jsonText = result.content.trim();
      if (jsonText.isEmpty) return null;

      final parsed = _parseJsonArray(jsonText);
      if (parsed.isEmpty) return null;

      final entries = <MemoryEntry>[];
      for (final item in parsed) {
        final content = item['content'] as String?;
        final tagStr = item['tag'] as String?;
        if (content == null || content.isEmpty) continue;

        final tag = MemoryTag.values.firstWhere(
          (t) => t.name == tagStr,
          orElse: () => MemoryTag.fact,
        );

        entries.add(MemoryEntry(
          id:
              'import_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_${entries.length}',
          tag: tag,
          content: content,
          importance: 0.5,
          createdAt: DateTime.now(),
          source: MemorySource.llm,
        ));
      }

      return entries.isNotEmpty ? entries : null;
    } catch (e) {
      PetLogger().error('MemoryImport', 'LLM extraction failed: $title', e);
      return null;
    }
  }

  /// 解析 JSON 数组，处理 LLM 可能的格式包装
  List<Map<String, dynamic>> _parseJsonArray(String text) {
    try {
      // 尝试直接解析
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
    } catch (_) {
      // 尝试提取 [...] 内容
      final match = RegExp(r'\[[\s\S]*\]').firstMatch(text);
      if (match != null) {
        try {
          final decoded = jsonDecode(match.group(0)!);
          if (decoded is List) {
            return decoded
                .whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList();
          }
        } catch (_) {}
      }
    }
    return [];
  }
}
