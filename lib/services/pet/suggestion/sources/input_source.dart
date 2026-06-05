// Flutter 3.24 / Dart 3.5
/// Token 消耗等级
enum TokenCostLevel { none, cheap, normal, expensive }

/// 一次上下文采集快照
class InputSnapshot {
  final String sourceId;
  final String summary;
  final Map<String, dynamic>? metadata;
  final DateTime collectedAt;

  InputSnapshot({
    required this.sourceId,
    required this.summary,
    this.metadata,
    DateTime? collectedAt,
  }) : collectedAt = collectedAt ?? DateTime.now();
}

/// 输入源插件接口：任何能给糯糯提供上下文的来源都实现这个
abstract class IInputSource {
  String get id;
  int get priority;
  bool get isEnabled;
  TokenCostLevel get costLevel;
  Future<InputSnapshot?> collect({required DateTime since});
  void dispose();
}
