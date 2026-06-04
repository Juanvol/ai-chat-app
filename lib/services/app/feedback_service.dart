import 'package:flutter/foundation.dart';
import '../../api/deepseek_client.dart';
import '../../models/feedback_entry.dart';
import 'storage_service.dart';

class FeedbackService extends ChangeNotifier {
  final StorageService _storage;
  List<FeedbackEntry> _entries = [];
  bool _isAnalyzing = false;

  FeedbackService({required StorageService storage}) : _storage = storage {
    _load();
  }

  List<FeedbackEntry> get entries => _entries;
  List<FeedbackEntry> get unprocessed => _entries.where((e) => !e.processed).toList();
  int get unprocessedCount => unprocessed.length;
  bool get isAnalyzing => _isAnalyzing;

  void _load() {
    _entries = _storage.getFbs();
    notifyListeners();
  }

  Future<void> add({
    required String conversationId,
    required String userMessage,
    required String aiResponse,
    String reason = '不满意',
  }) async {
    final e = FeedbackEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: conversationId,
      userMessage: userMessage,
      aiResponse: aiResponse,
      reason: reason,
      createdAt: DateTime.now(),
    );
    _entries.insert(0, e);
    await _storage.saveFb(e);
    notifyListeners();
  }

  Future<void> updateReason(String id, String reason) async {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i == -1) return;
    _entries[i].reason = reason;
    await _storage.saveFb(_entries[i]);
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _entries.removeWhere((e) => e.id == id);
    await _storage.delFb(id);
    notifyListeners();
  }

  String get adjustmentText => _storage.adjText ?? '';

  int get evolutionCount {
    final t = adjustmentText;
    if (t.isEmpty) return 0;
    return '---'.allMatches(t).length + 1;
  }

  int get processedCount => _entries.where((e) => e.processed).length;

  DateTime? get lastAnalysisTime {
    final processed = _entries.where((e) => e.processed).toList();
    if (processed.isEmpty) return null;
    processed.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return processed.first.createdAt;
  }

  List<AdjVersion> get adjustmentVersions {
    final t = adjustmentText;
    if (t.isEmpty) return [];
    return t.split('\n---\n').asMap().entries.map((e) {
      final versionIdx = e.key;
      final content = e.value.trim();
      final associated = _entries.where((fb) => fb.processed).toList();
      return AdjVersion(index: versionIdx, content: content, sourceCount: associated.length);
    }).toList().reversed.toList();
  }

  bool get hasNewAdjustment {
    final t = adjustmentText;
    if (t.isEmpty) return false;
    final lastSeen = _storage.get('last_seen_adj_ts', '') ?? '';
    final lastMod = _storage.get('adj_updated_at', '') ?? '';
    return lastMod.isNotEmpty && lastMod != lastSeen;
  }

  Future<void> markAdjustmentSeen() async {
    final lastMod = _storage.get('adj_updated_at', '') ?? '';
    await _storage.save('last_seen_adj_ts', lastMod);
    notifyListeners();
  }

  Future<void> saveAdjustmentText(String text) async {
    await _storage.setAdjText(text);
    await _storage.save('adj_updated_at', DateTime.now().toIso8601String());
    notifyListeners();
  }

  /// AI 自主分析未处理反馈，生成修正指令
  Future<void> autoGenerate({
    required LLMClient client,
    String baseUrl = 'https://api.deepseek.com',
    String? apiKey,
    String model = 'deepseek-chat',
    int maxTokens = 2048,
  }) async {
    final pending = unprocessed;
    if (pending.isEmpty) return;

    _isAnalyzing = true;
    notifyListeners();

    final entriesText = pending.map((e) =>
      '- 用户: ${e.userMessage.length > 100 ? '${e.userMessage.substring(0, 100)}...' : e.userMessage}\n'
      '  AI回答: ${e.aiResponse.length > 200 ? '${e.aiResponse.substring(0, 200)}...' : e.aiResponse}\n'
      '  原因: ${e.reason}'
    ).join('\n\n');

    final prompt = '''分析以下用户反馈，找出 AI 回答的共性问题，生成修正指令。

反馈记录：
$entriesText

请输出修正指令，格式：
### 修正指令
<具体的行为调整，3-5条>
### 问题摘要
<一句话总结主要问题>''';

    try {
      final msg = await client.send(
        history: [],
        userContent: prompt,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        maxTokens: maxTokens,
        thinkingEnabled: false,
        providerId: 'deepseek',
      );

      final result = msg.content;

      final adjStart = result.indexOf('### 修正指令');
      final probStart = result.indexOf('### 问题摘要');
      String newAdj = result;
      if (adjStart != -1 && probStart != -1) {
        newAdj = result.substring(adjStart + 8, probStart).trim();
      }

      final existing = adjustmentText;
      final updated = existing.isEmpty
          ? newAdj
          : '$existing\n\n---\n$newAdj';
      await saveAdjustmentText(updated);

      for (final e in pending) {
        e.processed = true;
        e.adjustmentResult = 'AI 已分析: ${result.length > 150 ? '${result.substring(0, 150)}...' : result}';
        await _storage.saveFb(e);
      }

      notifyListeners();
    } catch (e) {
      // 分析失败不阻塞
    }

    _isAnalyzing = false;
    notifyListeners();
  }
}

class AdjVersion {
  final int index;
  final String content;
  final int sourceCount;
  const AdjVersion({required this.index, required this.content, required this.sourceCount});
}
