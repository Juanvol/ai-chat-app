// Flutter 3.24 / Dart 3.5
import '../pet_logger.dart';

/// 打扰熔断器：防止宠物过度打扰用户
///
/// **三条规则：**
/// 1. 频率限制 — 1h 内 >3 次建议 → 静默 2h（自动解除）
/// 2. 解除惩罚 — 用户当天手动解除气泡 ≥3 次 → 当天频率 ×0.5
/// 3. 深夜降频 — 22:00-08:00 → 频率 ÷3
///
/// **使用方式：**
/// ```dart
/// // 入口点调用 refresh() 更新内部状态
/// gate.refresh();
/// // 然后读取纯查询 getter
/// if (gate.isSuppressed) return;
/// if (gate.isLateNight) { /* 概率跳过 */ }
/// ```
class DisturbGate {
  // ═══ 常量 ═══

  static const _maxSuggestionsPerHour = 3;
  static const _suppressDuration = Duration(hours: 2);
  static const _maxDismissalsPerDay = 3;
  static const _lateNightStart = 22;
  static const _lateNightEnd = 8;

  // ═══ 可变状态 ═══

  final List<DateTime> _recentSuggestionTimes = [];
  DateTime? _suppressUntil;
  int _dismissalsToday = 0;
  String _dismissalDateKey = '';

  // ═══ 纯查询 getter（无副作用）═══

  /// 当前是否在静默期
  bool get isSuppressed {
    if (_suppressUntil == null) return false;
    return DateTime.now().isBefore(_suppressUntil!);
  }

  /// 距静默结束的秒数（0 = 未静默），供 UI
  int get suppressRemainingSeconds {
    if (_suppressUntil == null) return 0;
    final r = _suppressUntil!.difference(DateTime.now()).inSeconds;
    return r > 0 ? r : 0;
  }

  /// 今日解除次数
  int get dismissalsToday => _dismissalsToday;

  /// 深夜降频是否生效
  bool get isLateNight {
    final h = DateTime.now().hour;
    return h >= _lateNightStart || h < _lateNightEnd;
  }

  /// 综合频率系数（1.0 = 正常，值越小建议越少）
  ///
  /// 供 PetAgentCore 调整评估间隔使用。
  double get frequencyMultiplier {
    double m = 1.0;
    if (_dismissalsToday >= _maxDismissalsPerDay) m *= 0.5;
    if (isLateNight) m /= 3.0;
    return m;
  }

  // ═══ 状态刷新（入口点，有副作用）═══

  /// 刷新内部状态：自动解除过期静默 + 跨天重置计数器
  ///
  /// 调用方应在每次检查前调用此方法。
  void refresh() {
    _ensureDateKey();
    _checkSuppressExpiry();
  }

  // ═══ 记录方法（事件驱动）═══

  /// 记录一次建议已发出 → 更新滑动窗口 → 检查熔断阈值
  void recordSuggestion() {
    final now = DateTime.now();
    refresh();

    _recentSuggestionTimes.removeWhere(
        (t) => now.difference(t).inHours >= 1);
    _recentSuggestionTimes.add(now);

    PetLogger().trace('DisturbGate',
        'suggestion #${_recentSuggestionTimes.length}/h');

    if (_recentSuggestionTimes.length > _maxSuggestionsPerHour) {
      _suppressUntil = now.add(_suppressDuration);
      PetLogger().info('DisturbGate',
          'CIRCUIT BREAKER: suppress until $_suppressUntil');
    }
  }

  /// 记录一次用户解除（互动打断气泡 → 解除计数 +1）
  void recordDismissal() {
    refresh();
    _dismissalsToday++;
    PetLogger().info('DisturbGate',
        'dismissal $_dismissalsToday/$_maxDismissalsPerDay today');
  }

  // ═══ 内部 ═══

  void _checkSuppressExpiry() {
    if (_suppressUntil != null &&
        !DateTime.now().isBefore(_suppressUntil!)) {
      PetLogger().info('DisturbGate', 'suppression auto-lifted');
      _suppressUntil = null;
    }
  }

  void _ensureDateKey() {
    final todayKey = _dateKey(DateTime.now());
    if (_dismissalDateKey != todayKey) {
      _dismissalDateKey = todayKey;
      _dismissalsToday = 0;
    }
  }

  static String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  // ═══ 生命周期 ═══

  void dispose() {
    _recentSuggestionTimes.clear();
    _suppressUntil = null;
    _dismissalsToday = 0;
  }
}
