// Flutter 3.24 / Dart 3.5
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/model_config.dart';
import '../services/conversation_service.dart';
import '../services/memory_service.dart';

Future<int> extractMemories(BuildContext context) async {
  final cs = context.read<ConversationService>();
  final ms = context.read<MemoryService>();
  final cov = cs.currentConversation;
  if (cov == null || cov.messages.isEmpty) return 0;

  final model = ModelConfig.builtIn.firstWhere(
    (m) => m.id == cs.storage.selModel,
    orElse: () => ModelConfig.builtIn.first,
  );
  final provider = ModelConfig.providers.firstWhere(
    (p) => p.id == model.providerId,
    orElse: () => ModelConfig.providers.first,
  );
  final providerKey = cs.storage.get('${provider.id}_key', '') ?? '';

  final msgs = cov.messages
      .where((m) => !m.isStreaming)
      .map((m) => '${m.role == 'user' ? '用户' : 'AI'}: ${m.content}')
      .join('\n');

  final prompt = '''分析以下对话，提取关于用户当前任务和目标的信息，用 JSON 数组返回：
[
  {"content": "记忆内容", "importance": 1-5}
]

重要度说明：
5=核心目标（用户在做的项目、长期目标）
4=当前任务（正在解决的具体问题）
3=已做决策（已确定的方向、已排除的方案）
2=技术约束（使用的技术栈、环境限制）
1=临时提及（可能相关的背景信息）

注意：不要提取用户的个人偏好、习惯、喜好。只提取与任务协作相关的信息。

对话：
$msgs

只返回 JSON，不要其他内容。''';

  final msg = await cs.client.send(
    history: [],
    userContent: prompt,
    baseUrl: provider.baseUrl,
    apiKey: providerKey.isNotEmpty ? providerKey : cs.client.apiKey,
    model: model.modelId,
    maxTokens: 2048,
    thinkingEnabled: false,
    providerId: model.providerId,
  );

  final jsonStr = msg.content.trim();
  final start = jsonStr.indexOf('[');
  final end = jsonStr.lastIndexOf(']');
  if (start == -1 || end == -1 || start >= end) return 0;

  final list = _parseJsonList(jsonStr.substring(start, end + 1));
  int added = 0;
  for (final item in list) {
    if (item['content'] is String && (item['content'] as String).isNotEmpty) {
      ms.add(item['content'] as String, importance: (item['importance'] as num?)?.toInt() ?? 3);
      added++;
    }
  }
  return added;
}

List<Map<String, dynamic>> _parseJsonList(String s) {
  try {
    final decoded = jsonDecode(s);
    if (decoded is List) return decoded.cast<Map<String, dynamic>>();
  } catch (_) {}
  return [];
}
