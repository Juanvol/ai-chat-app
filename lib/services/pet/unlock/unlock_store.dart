// Flutter 3.24 / Dart 3.5
import 'package:hive/hive.dart';
import '../suggestion/models/suggestion.dart';
import '../pet_logger.dart';

/// 渐进解锁存储：记录首次互动日期，按时间解锁建议层级
///
/// 解锁顺序（非对称，与 enum index 不同）：
/// Day 0-2  → L1 闲聊气泡
/// Day 3-6  → L2 场景感知
/// Day 7-13 → L4 晚间总结/主动提醒
/// Day 14+  → L3 深度建议（全部解锁）
class UnlockStore {
  static const _boxName = 'pet_unlock';
  static const _keyFirstInteraction = 'first_interaction_ms';
  static const _keyOnboardingDone = 'onboarding_done';
  Box? _box;

  DateTime? _firstInteractionDate;
  bool _onboardingDone = false;

  UnlockStore();

  /// 测试构造 — 注入固定日期模拟任意陪伴天数
  UnlockStore.test({DateTime? firstInteractionDate, bool onboardingDone = true})
      : _firstInteractionDate = firstInteractionDate,
        _onboardingDone = onboardingDone;

  DateTime? get firstInteractionDate => _firstInteractionDate;
  bool get onboardingDone => _onboardingDone;

  /// 距离首次互动的天数（0 = 今天刚开始）
  int get daysSinceFirstInteraction {
    if (_firstInteractionDate == null) return 0;
    return DateTime.now().difference(_firstInteractionDate!).inDays;
  }

  /// 当前解锁的建议层级上限
  SuggestionLevel get unlockedLevel {
    final days = daysSinceFirstInteraction;
    if (days >= 14) return SuggestionLevel.l3; // 全部解锁
    if (days >= 7) return SuggestionLevel.l4;  // 晚间总结
    if (days >= 3) return SuggestionLevel.l2;  // 场景感知
    return SuggestionLevel.l1;                  // 闲聊
  }

  /// 解锁顺序数值（非 enum index）— L4 在 L3 之前解锁
  static int unlockTier(SuggestionLevel level) => switch (level) {
        SuggestionLevel.l1 => 1,
        SuggestionLevel.l2 => 2,
        SuggestionLevel.l4 => 3,
        SuggestionLevel.l3 => 4,
      };

  /// 给定层级是否已解锁
  bool isUnlocked(SuggestionLevel level) {
    return unlockTier(level) <= unlockTier(unlockedLevel);
  }

  /// 下一个解锁目标（供 UI/上下文提示），null = 全部已解锁
  ({int days, String label})? get nextUnlock {
    final days = daysSinceFirstInteraction;
    if (days < 3) return (days: 3 - days, label: '场景感知');
    if (days < 7) return (days: 7 - days, label: '晚间总结');
    if (days < 14) return (days: 14 - days, label: '深度建议');
    return null;
  }

  /// 标记首次互动（幂等）
  Future<void> markFirstInteraction() async {
    if (_firstInteractionDate != null) return;
    _firstInteractionDate = DateTime.now();
    await _save();
    PetLogger().info(
        'UnlockStore', 'first interaction: $_firstInteractionDate');
  }

  /// 标记引导完成（幂等）
  Future<void> markOnboardingDone() async {
    if (_onboardingDone) return;
    _onboardingDone = true;
    await _save();
    PetLogger().info('UnlockStore', 'onboarding done');
  }

  /// 从 Hive 加载
  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    final ms = _box?.get(_keyFirstInteraction);
    if (ms is int && ms > 0) {
      _firstInteractionDate = DateTime.fromMillisecondsSinceEpoch(ms);
    }
    _onboardingDone = _box?.get(_keyOnboardingDone) == true;
    PetLogger().info('UnlockStore',
        'init: days=$daysSinceFirstInteraction level=${unlockedLevel.name} onboardingDone=$_onboardingDone');
  }

  Future<void> _save() async {
    if (_firstInteractionDate != null) {
      await _box?.put(
        _keyFirstInteraction,
        _firstInteractionDate!.millisecondsSinceEpoch,
      );
    }
    await _box?.put(_keyOnboardingDone, _onboardingDone);
  }

  void dispose() {
    _box = null;
    _firstInteractionDate = null;
  }
}
