// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../../pet/pet_controller.dart';
import '../../api/deepseek_client.dart';
import '../../models/pet_state.dart';
import './pet_service.dart';
import './pet_ai_service.dart';
import './pet_diary_service.dart';
import './pet_logger.dart';
import 'pet_token_service.dart';
import 'pet_brain.dart';
import 'pet_bubble_manager.dart';
import 'pet_agent_core.dart';
import 'knowledge/knowledge_base.dart' hide SuggestionLevel;
import 'knowledge/diary/diary_repository_hive.dart';
import 'knowledge/diary/diary_store.dart';
import 'knowledge/diary/diary_summarizer.dart';
import 'knowledge/memory/memory_repository_hive.dart';
import 'knowledge/memory/memory_store.dart';
import 'knowledge/memory/memory_organizer.dart';
import 'suggestion/suggestion_engine.dart';
import 'suggestion/budget_gate.dart';
import 'suggestion/suggestion_store.dart';
import 'suggestion/models/suggestion.dart';
import 'persona/persona_store.dart';
import 'unlock/unlock_store.dart';

/// 全局宠物浮窗控制器
final petOverlayController = PetOverlayController();

class PetOverlayController {
  static const _overlay = MethodChannel('com.example.deepseek_chat/pet_overlay');

  PetController? _controller;
  PetAiService? _aiService;
  int _batteryLevel = 100;
  bool _charging = false;
  bool _started = false;

  // ── 状态去重：避免向原生发送冗余的 MethodChannel 命令 ──
  PetStatus? _lastSyncedStatus;
  String? _lastSyncedEmoji;
  DateTime _lastInteractionAt = DateTime.now();

  // PetBrain 行为决策
  final _brain = BehaviorWeights();
  final _bubbleMgr = PetBubbleManager();
  final _rhythm = UserRhythm();
  final _dailyMood = DailyMood.today();
  Timer? _brainTimer;
  bool _bubbleShowing = false;

  // ─── 新知识库（D1-D2） ───
  KnowledgeBase? _knowledgeBase;
  bool _kbInitializing = false;

  /// D8: 知识库就绪通知 — UI 通过 ListenableBuilder 监听
  final ValueNotifier<bool> kbReady = ValueNotifier<bool>(false);

  /// 公开知识库访问（供 UI 和 D8 ContextCollector 使用）
  KnowledgeBase? get knowledgeBase => _knowledgeBase;

  /// 公开建议存储（供建议历史页面读取）
  SuggestionStore? get suggestionStore => _suggestionStore;

  SuggestionStore? _suggestionStore;
  // ignore: unused_field — 生命周期由 PetOverlayController 管理
  SuggestionEngine? _suggestionEngine;

  // ── 人格存储（D8 Phase 2） ──
  PersonaStore? _personaStore;

  /// 公开人格存储（供 UI 读取/编辑）
  PersonaStore? get personaStore => _personaStore;

  // ── 渐进解锁（D8 Phase 2c） ──
  UnlockStore? _unlockStore;

  /// 公开解锁状态（供 UI 读取）
  UnlockStore? get unlockStore => _unlockStore;

  // ── LLM 定时调度状态 ──
  String? _lastSummaryDateKey; // 上次生成日总结的日期键，避免重复触发
  DateTime? _lastOrganizeCheck; // 上次检查记忆整理的时间
  DateTime? _lastIdleReminderAt; // 上次空闲过长提醒的时间（防重复）
  String? _lastGreetingDateKey; // 上次早安/晚安提醒日期，避免每日重复

  bool get isActive => _started;

  /// 宠物当前自称（默认 "糯糯"，可通过 PersonaStore 修改）
  String get petSelfRef {
    final r = _personaStore?.persona.style.selfReference;
    return (r != null && r.isNotEmpty) ? r : '糯糯';
  }
  String get personaName {
    final n = _personaStore?.persona.name;
    return (n != null && n.isNotEmpty) ? n : '糯糯';
  }
  // 保留旧名兼容
  String get _selfRef => petSelfRef;

  /// 初始化知识库（独立于宠物启动，UI 可随时调用）
  Future<void> ensureKB() async {
    if (_knowledgeBase != null || _kbInitializing) return;
    _kbInitializing = true;
    PetLogger().info('Overlay', 'ensureKB() BEGIN');

    try {
      final diaryRepo = DiaryRepoHive();
      await diaryRepo.init();
      final memoryRepo = MemoryRepoHive();
      await memoryRepo.init();

      // 获取 API Key（用于 LLM 日总结 + 记忆整理）
      String? apiKey;
      try {
        final settingsBox = await Hive.openBox('settings');
        apiKey = settingsBox.get('api_key') as String?;
        if (apiKey == null || apiKey.isEmpty) {
          // fallback: 尝试 deepseek_key
          apiKey = settingsBox.get('deepseek_key') as String?;
        }
      } catch (_) {}
      final llmClient = apiKey != null && apiKey.isNotEmpty
          ? LLMClient(apiKey: apiKey)
          : null;

      final memoryStore = MemoryStore(
        repo: memoryRepo,
        diaryRepo: diaryRepo,
        tokenService: PetTokenService.instance,
        organizer: llmClient != null ? MemoryOrganizer(client: llmClient) : null,
      );

      final diaryStore = DiaryStore(
        repo: diaryRepo,
        onEventRecorded: (event) {
          memoryStore.extractFrom(event);
        },
        tokenService: PetTokenService.instance,
        summarizer: llmClient != null ? DiarySummarizer(client: llmClient) : null,
      );

      _knowledgeBase = KnowledgeBase(
        diaryStore: diaryStore,
        memoryStore: memoryStore,
        diaryRepo: diaryRepo,
        memoryRepo: memoryRepo,
      );

      _unlockStore = UnlockStore();
      await _unlockStore!.init();
      await _unlockStore!.markFirstInteraction();

      _personaStore = PersonaStore();
      await _personaStore!.init();
      _knowledgeBase!.updatePersona(_personaStore!.persona);
      _personaStore!.addListener(() {
        _knowledgeBase?.updatePersona(_personaStore!.persona);
      });

      // SuggestionEngine 需要 KB，但不需要 pet overlay 运行
      final suggestionEngine = SuggestionEngine(
        knowledgeBase: _knowledgeBase!,
        budgetGate: BudgetGate(getRemaining: PetTokenService.instance.getBudgetRemaining),
        unlockStore: _unlockStore,
      );
      _suggestionStore = suggestionEngine.store;
      _suggestionEngine = suggestionEngine;
      suggestionEngine.onSuggestionPublished = (level) {
        _syncSuggestionEmotion(level);
      };
      PetAgentCore.shared?.attachSuggestionEngine(suggestionEngine);

      // ── 迁移旧日记数据（pet_diary → pet_diary_v2）──
      _migrateOldDiary(diaryStore);

      PetLogger().info('Overlay', 'ensureKB() DONE');
      kbReady.value = true;

      // ── D8j+D8l: 首次引导气泡序列（必须在 unlockStore init 后）─
      if (!_unlockStore!.onboardingDone) {
        Future.delayed(const Duration(seconds: 3), () {
          if (!_started) return;
          _showOnboardingBubbles();
        });
      }
    } catch (e) {
      PetLogger().error('Overlay', 'ensureKB() failed', e);
    } finally {
      _kbInitializing = false;
    }
  }

  /// 一次性迁移：将旧 pet_diary Box 中的日记导入新 DiaryStore
  Future<void> _migrateOldDiary(DiaryStore diaryStore) async {
    try {
      final oldBox = await Hive.openBox('pet_diary');
      if (oldBox.isEmpty) return;
      // 检查迁移标记
      final configBox = await Hive.openBox('pet_config');
      if (configBox.get('diary_migrated_v2') == true) return;

      int migrated = 0;
      for (final key in oldBox.keys) {
        try {
          final raw = oldBox.get(key);
          if (raw is Map) {
            final type = raw['type'] as String? ?? 'event';
            final content = raw['content'] as String? ?? '';
            await diaryStore.recordEvent(type, detail: content);
            migrated++;
          }
        } catch (_) {}
      }
      if (migrated > 0) {
        await configBox.put('diary_migrated_v2', true);
        PetLogger().info('Overlay', '_migrateOldDiary: $migrated entries migrated');
      } else {
        await configBox.put('diary_migrated_v2', true);
      }
    } catch (e) {
      PetLogger().error('Overlay', '_migrateOldDiary failed', e);
    }
  }

  void init() {
    _overlay.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTouch':
          final a = call.arguments as Map?;
          final type = a?['type'] as String? ?? '';
          final x = (a?['x'] as num?)?.toDouble() ?? 0;
          final y = (a?['y'] as num?)?.toDouble() ?? 0;
          PetLogger().trace('Overlay', '$type ($x, $y)');

          switch (type) {
            case 'tap':
              _onUserInteraction(type: 'tap');
            case 'pet':
              _onUserInteraction(type: 'pet');
              if (_controller != null) {
                _controller!.pet();
                _cmd('playAnim', {'anim': 'jump'});
                _showBubbleWithDismiss('好开心~ 💕');
                _recordDiary('pet');
              }
            case 'feed':
              _onUserInteraction(type: 'feed');
              if (_controller != null) {
                _controller!.feed();
                _cmd('playAnim', {'anim': 'talking'});
                Future.delayed(const Duration(seconds: 2), () => _syncAnim());
                _recordDiary('feed');
              }
            case 'play':
              _onUserInteraction(type: 'play');
              if (_controller != null) {
                _controller!.play();
                _cmd('playAnim', {'anim': 'jump'});
                Future.delayed(const Duration(seconds: 2), () => _syncAnim());
                _recordDiary('play');
              }
            case 'status':
              // 快捷菜单 → 查看状态（通过 pet_agent_bridge 通知主应用导航）
              _navigateToPetCenter();
            case 'diary':
              // 快捷菜单 → 查看日记
              _navigateToPetDiary();
            case 'screen':
              if (x == -1) {
                _cmd('playAnim', {'anim': 'sleeping'});
              } else {
                _syncAnim();
              }
            case 'battery':
              _batteryLevel = x.toInt();
              _charging = y == 1;
              if (_batteryLevel < 15 && !_charging && !_bubbleShowing) {
                _showBubbleWithDismiss('好困…电量不足了💤', duration: const Duration(seconds: 5));
              }
            case 'arrive':
              PetLogger().trace('Overlay', 'pet arrived at ($x, $y)');
            case 'pokeCount':
              final count = (a?['count'] as num?)?.toInt() ?? 0;
              PetLogger().trace('Overlay', 'pokeCount=$count');
          }
      }
    });
  }

  /// Wire 2: 从 main.dart Provider 创建时绑定 Controller 的生命周期
  void attachController(PetController controller) {
    _controller = controller;
    // ── Wire 2: 状态变更 → 原生动画 ──
    _controller!.onStateChanged = (state) {
      PetLogger().trace('Overlay', 'onStateChanged: status=${state.status.name}');
      _syncAnim();
    };
  }

  Future<void> start() async {
    if (_started) { PetLogger().warn('Overlay', 'start SKIP: already started'); return; }
    PetLogger().info('Overlay', 'start() BEGIN');

    PetState saved = PetState();
    try { saved = await PetService.loadState(); } catch (e) { PetLogger().error('Overlay', 'loadState failed', e); }

    // 复用 Provider 创建的共享 PetController，确保应用内按钮和浮窗操作同一状态
    final shared = PetController.shared;
    if (shared != null) {
      shared.restoreFromState(saved);
      shared.onStateChanged = (s) {
        try { PetService.saveState(s); } catch (e) { PetLogger().error('Overlay', 'saveState failed', e); }
        _syncState();
      };
      _controller = shared;
    } else {
      _controller = PetController(
        initialState: saved,
        onStateChanged: (s) {
          try { PetService.saveState(s); } catch (e) { PetLogger().error('Overlay', 'saveState failed', e); }
          _syncState();
        },
      );
    }
    _controller!.start();

    // ── D4: 养成里程碑 → 特殊气泡 + 日记 ──
    _controller!.onMilestoneReached = (tier, affection) {
      final (bubble, anim) = switch (tier) {
        1 => ('好感度达到 100！主人对我越来越好了~ 💕 解锁新关系：初识', 'wave'),
        2 => ('好感度达到 500！$petSelfRef已经成为主人的好朋友了~ 🎉 解锁新关系：熟悉', 'jump'),
        3 => ('好感度达到 1000！$petSelfRef和主人心有灵犀~ ✨ 解锁新关系：默契', 'talking'),
        _ => ('', 'idle'),
      };
      if (bubble.isNotEmpty) {
        _cmd('playAnim', {'anim': anim, 'emotionSpeed': 1.2});
        _showBubbleWithDismiss(bubble, duration: const Duration(seconds: 6));
        _recordDiary('milestone', detail: bubble);
        Future.delayed(const Duration(seconds: 3), () => _syncAnim());
      }
    };

    _aiService = PetAiService();
    await _aiService!.init();

    // ── 初始化知识库（后台进行，不阻塞宠物出现） ──
    ensureKB(); // fire-and-forget, kbReady 就绪后 UI 自动刷新

    // 同步宠物名到 Kotlin 原生层
    Future.delayed(const Duration(milliseconds: 300), () {
      final name = personaName;
      final selfRef = petSelfRef;
      _cmd('setPetName', {'name': name, 'selfRef': selfRef});
    });

    _aiService!.startProactiveTimer((s) {
      _recordDiary('suggestion', detail: s);
      // D8e: 根据内容推断来源
      final hour = DateTime.now().hour;
      final source = switch (hour) {
        >= 6 && < 9 => '早安问候',
        >= 12 && < 14 => '午间关心',
        >= 18 && < 21 => '傍晚陪伴',
        >= 21 || < 6 => '晚间守护',
        _ => '$_selfRef的关心',
      };
      final displayText = '$s  （$source）';
      // D8b: 可点击气泡
      _showChatBubble(displayText, duration: const Duration(seconds: 8));
      // 记录到建议引擎
      _suggestionEngine?.recordSuggestion(text: s, level: SuggestionLevel.l1, source: source);
      _syncSuggestionEmotion(SuggestionLevel.l1);
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      _syncAnim();
      _syncScale();
      PetService.loadConfig().then((c) {
        syncTransparentIdle(c.idleTransparentMinutes);
        syncRenderScale(c.renderScale);
      }).catchError((e) {
        PetLogger().error('Overlay', 'syncConfig failed', e);
      });
    });
    _startBrainLoop();
    // Onboarding 已移入 ensureKB()（避免 KB 未就绪时的竞态）
    // 每3天记忆整理检查（首次在start后5分钟触发）
    Future.delayed(const Duration(minutes: 5), () {
      _knowledgeBase?.memoryStore.organizeIfNeeded();
    });
    PetLogger().info('Overlay', 'start done (PetBrain v2)');
    _started = true;
  }

  Future<void> stop() async {
    _stopBrainLoop();
    _started = false;
    _aiService?.dispose();
    _aiService = null;
    _suggestionEngine?.dispose();
    _suggestionEngine = null;
    // KB/Persona/Unlock 独立于宠物运行，不随 stop 销毁
    _suggestionStore = null;
    _lastSummaryDateKey = null;
    _lastOrganizeCheck = null;
    _lastIdleReminderAt = null;
    _lastGreetingDateKey = null;
    _lastSyncedStatus = null;
    _lastSyncedEmoji = null;
    _lastInteractionAt = DateTime.now();
    if (_controller != null) {
      try { PetService.saveState(_controller!.state); } catch (e) { PetLogger().error('Overlay', 'stop saveState failed', e); }
      _controller!.onStateChanged = null;
      _controller!.stop();       // 停止衰减定时器
      if (!identical(_controller, PetController.shared)) {
        _controller!.dispose();  // 仅 dispose 非共享实例
      }
      _controller = null;
    }
    _cmd('close');
    PetLogger().info('Overlay', 'stop()');
  }

  // ═══════════════════════════════════════════
  // PetBrain 决策循环（替代旧 Timer 空闲行为）
  // ═══════════════════════════════════════════

  void _startBrainLoop() {
    _brainTimer?.cancel();
    _brainTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_started) return;
      _brainTick();
    });
  }

  void _stopBrainLoop() {
    _brainTimer?.cancel();
    _brainTimer = null;
    _bubbleShowing = false;
  }

  /// 冒泡 + 自动隐藏
  void _showBubbleWithDismiss(String text, {Duration duration = const Duration(seconds: 3)}) {
    _bubbleShowing = true;
    _cmd('showBubble', {'text': text, 'durationMs': duration.inMilliseconds});
    PetLogger().trace('Overlay', 'bubble: $text');
    Future.delayed(duration, () {
      _cmd('hideBubble');
      _bubbleShowing = false;
    });
  }

  /// D8b: 显示可点击的建议气泡 — 点击后弹出迷你聊天
  void _showChatBubble(String text, {String? context, Duration duration = const Duration(seconds: 8)}) {
    _bubbleShowing = true;
    _cmd('showChatBubble', {'text': text, 'context': context ?? text});
    PetLogger().trace('Overlay', 'chatBubble: $text');
    Future.delayed(duration, () {
      _cmd('hideBubble');
      _bubbleShowing = false;
    });
  }

  /// D5+D8i: 用户交互公共处理 — 深度唤醒 + 解除追踪 + 节奏记录 + 日记
  void _onUserInteraction({required String type}) {
    // 深度休眠唤醒
    if (_controller?.isDeepSleeping == true) {
      _showWakeUpBubble();
    }
    // 用户互动打断气泡 → 计为一次解除
    if (_bubbleShowing) {
      _suggestionEngine?.recordDismissal();
    }
    _rhythm.recordInteraction();
    _lastInteractionAt = DateTime.now();
    _recordDiary(type);
  }

  /// D5: 深度休眠唤醒气泡
  void _showWakeUpBubble() {
    final hour = DateTime.now().hour;
    final greeting = switch (hour) {
      >= 6 && < 12 => '主人早安！$petSelfRef睡醒了~ ☀️',
      >= 12 && < 18 => '主人下午好！$petSelfRef一直在等你~ 🌤️',
      >= 18 && < 22 => '主人晚上好！$petSelfRef想你了~ 🌙',
      _ => '主人还没睡呀...$petSelfRef陪你~ 🌙',
    };
    _showBubbleWithDismiss(greeting, duration: const Duration(seconds: 5));
    _recordDiary('wake', detail: '主人回来了，深度休眠结束~');
    PetLogger().info('Overlay', 'deepSleep wakeup: $greeting');
  }

  /// D8j+D8l: 首次引导气泡序列（糯糯自我介绍）
  void _showOnboardingBubbles() {
    PetLogger().info('Overlay', 'onboarding: start');
    _showBubbleWithDismiss('嗨！我是$petSelfRef~ 🎉',
        duration: const Duration(seconds: 2));
    Future.delayed(const Duration(seconds: 3), () {
      if (!_started) return;
      _showBubbleWithDismiss('我会陪在你身边，偶尔给你一些小建议~',
          duration: const Duration(seconds: 3));
    });
    Future.delayed(const Duration(seconds: 6), () {
      if (!_started) return;
      _showBubbleWithDismiss('随着相处时间变长，我会越来越了解你哦 💕',
          duration: const Duration(seconds: 4));
    });
    Future.delayed(const Duration(seconds: 11), () {
      _unlockStore?.markOnboardingDone();
      PetLogger().info('Overlay', 'onboarding: done');
    });
  }

  /// D8k: 建议层级 → 情绪动画同步到 Kotlin 层
  void _syncSuggestionEmotion(SuggestionLevel level) {
    final (:emoji, :anim) = SuggestionEngine.emotionForLevel(level);
    _cmd('showEmoji', {'emoji': emoji});
    _cmd('playAnim', {'anim': anim, 'emotionSpeed': 1.0});
    PetLogger().trace('Overlay', 'emotion sync: $level → $emoji $anim');
  }

  void _brainTick() {
    final now = DateTime.now();

    // ── LLM 定时调度（每 45 秒轻量检查） ──
    _checkDailySummary(now);
    _checkMemoryOrganize(now);
    _checkIdleReminder(now);
    _checkSmartGreeting(now);
    final s = _controller?.state;
    final al = PetAgentCore.shared?.attentionLevel ?? AttentionLevel.l3;

    _brain.applyContext(
      hour: now.hour,
      hunger: s?.hunger ?? 80,
      energy: s?.energy ?? 80,
      mood: (s?.mood ?? 50) / 100,
      al: al,
    );

    // 每日心情偏移
    final moodMod = _dailyMood.moodSeed;
    _brain.wander = (_brain.wander * moodMod * 2).round();
    _brain.speakBubble = (_brain.speakBubble * moodMod * 2).round();

    // 空闲分层（从最近交互时间戳计算，替代每秒定时器）
    final idleSeconds = now.difference(_lastInteractionAt).inSeconds;
    final tier = IdleTierExt.fromIdleSeconds(idleSeconds);

    final action = _brain.pickAction();

    // ── P2-②: Agent 动作冷却 — 如果 PetAgentCore 最近有动作，Brain 进入安静模式 ──
    final agentCooldown = PetAgentCore.lastActionAt != null &&
        now.difference(PetAgentCore.lastActionAt!).inSeconds < 45;
    final quietMode = agentCooldown && idleSeconds < 120;

    PetLogger().trace('Overlay', 'brainTick: $action tier=${tier.name} idle=${idleSeconds}s quiet=$quietMode');

    // 安静模式下只允许最基础的 idle 行为，避免覆盖 Agent 的决策
    if (quietMode && action != 'idleBreath' && action != 'lookAround') {
      PetLogger().trace('Overlay', 'brainTick SKIP (quiet mode): $action suppressed');
      return;
    }

    switch (action) {
      case 'wander':
        final rng = Random();
        // 随机目标（需要在 PetView 初始化后由物理引擎的边界限制）
        final tx = rng.nextDouble() * 800 + 50;
        final ty = rng.nextDouble() * 1000 + 200;
        _cmd('moveTo', {'x': tx, 'y': ty, 'speed': 150});
        _cmd('playAnim', {'anim': 'walk'});

      case 'sitDown':
        _cmd('playAnim', {'anim': 'sit'});
        // 2 分钟后站起
        Future.delayed(const Duration(minutes: 2), () {
          _cmd('playAnim', {'anim': 'idle'});
        });

      case 'rareAction':
        _cmd('playAnim', {'anim': 'idle', 'emotionSpeed': 1.5});
        final b = _bubbleMgr.pick(category: 'surprise', period: DayPeriodExt.fromHour(now.hour));
        if (b != null) _cmd('showBubble', {'text': b, 'durationMs': 4000});

      case 'hungryBubble':
        final b = _bubbleMgr.pick(category: 'hungry', period: DayPeriodExt.fromHour(now.hour));
        if (b != null) _cmd('showBubble', {'text': b, 'durationMs': 3000});

      case 'speakBubble':
        final b = _bubbleMgr.pick(category: 'affection', period: DayPeriodExt.fromHour(now.hour));
        if (b != null) _cmd('showBubble', {'text': b, 'durationMs': 3000});

      case 'sleep':
        _cmd('playAnim', {'anim': 'sleeping'});

      default:
        // idleBreath / lookAround → 保持 idle
        if (tier == IdleTier.tier1) {
          // 呼吸缩放由 Kotlin 端物理引擎处理
        } else if (tier == IdleTier.tier2) {
          // 微动由 FrameBlender 处理
        }
    }
  }

  void _syncState() {
    if (!_started || _controller == null) return;
    final s = _controller!.state;

    final emoji = switch (s.status) {
      PetStatus.hungry => '🍖',
      PetStatus.eating => '😋',
      PetStatus.happy => '😸',
      PetStatus.sleepy || PetStatus.sleeping => '💤',
      PetStatus.talking => '💬',
      PetStatus.idle => s.mood > 60 ? '😊' : s.mood > 30 ? '😐' : '😞',
    };

    // ── 状态去重：状态和 emoji 都没变则跳过 ──
    if (_lastSyncedStatus == s.status && _lastSyncedEmoji == emoji) return;
    _lastSyncedStatus = s.status;
    _lastSyncedEmoji = emoji;

    PetLogger().info('Overlay', 'sync: status=${s.status.name} hunger=${s.hunger} mood=${s.mood.toStringAsFixed(0)} energy=${s.energy} affection=${s.affection}');
    _cmd('showEmoji', {'emoji': emoji});
    _syncAnim(); // 内部有 _lastSyncedStatus 二次守卫，状态同则 skip
  }

  /// Wire 2: 根据 Controller 当前状态同步原生动画 + 气泡
  /// 调用方（_syncState / onStateChanged）已做去重，这里直接执行
  void _syncAnim() {
    if (!_started || _controller == null) return;
    final s = _controller!.state;
    final status = s.status;

    switch (status) {
      case PetStatus.hungry:
        _cmd('playAnim', {'anim': 'hungry'});
        _showBubbleIfNeeded('好饿喵...🍖');
        break;
      case PetStatus.sleepy:
        _cmd('playAnim', {'anim': 'sleeping'});
        _showBubbleIfNeeded('好困...💤');
        break;
      case PetStatus.eating:
        _cmd('playAnim', {'anim': 'talking'});
        break;
      case PetStatus.happy:
        _cmd('playAnim', {'anim': 'wave'});
        break;
      case PetStatus.talking:
        _cmd('playAnim', {'anim': 'talking'});
        break;
      case PetStatus.sleeping:
        _cmd('playAnim', {'anim': 'sleeping'});
        break;
      case PetStatus.idle:
        _cmd('playAnim', {'anim': 'idle'});
        break;
    }
  }

  /// 防重复气泡：仅在当前无气泡时发送
  void _showBubbleIfNeeded(String text) {
    if (!_bubbleShowing) {
      _showBubbleWithDismiss(text);
    }
  }

  /// 供外部调用（如设置页修改大小后即时生效）
  void syncScale() => _syncScale();

  /// 同步空闲透明超时到 Kotlin（设置页修改后即时生效）
  void syncTransparentIdle(int minutes) {
    if (!_started) return;
    _cmd('setTransparentIdle', {'minutes': minutes});
  }

  /// 同步视觉缩放到 Kotlin（设置页修改后即时生效）
  void syncRenderScale(double scale) {
    if (!_started) return;
    _cmd('setRenderScale', {'scale': scale});
  }

  void _syncScale() {
    if (!_started) { PetLogger().warn('Overlay', '_syncScale SKIP: not started'); return; }
    PetService.loadConfig().then((config) {
      final scale = config.petScale;
      const baseSize = 156.0;
      final w = (baseSize * scale).round();
      final h = (baseSize * scale).round();
      PetLogger().info('Overlay', 'scale sync: ${scale.toStringAsFixed(1)} → ${w}x${h}dp');
      _cmd('setSize', {'width': w, 'height': h});
    }).catchError((e) {
      PetLogger().error('Overlay', '_syncScale failed', e);
    });
  }

  void _cmd(String cmd, [Map<String, dynamic>? args]) {
    // 生产环境跳过 trace（避免 args.toString() 分配 Map 字符串）
    if (kDebugMode) {
      PetLogger().trace('Overlay', 'cmd: $cmd ${args?.toString() ?? ""}');
    }
    try {
      _overlay.invokeMethod('cmd', {'cmd': cmd, 'args': args});
    } catch (e) {
      PetLogger().error('Overlay', 'cmd $cmd failed (channel not ready?)', e);
    }
  }

  /// 每日21:00-21:30检查是否需要生成日总结
  void _checkDailySummary(DateTime now) {
    // 仅在21:00-21:30之间检查
    if (now.hour != 21) return;

    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    // 今天已生成过 → 跳过
    if (_lastSummaryDateKey == todayKey) return;

    _lastSummaryDateKey = todayKey;
    final kb = _knowledgeBase;
    if (kb == null) return;

    PetLogger().info('Overlay', 'dailySummary: triggering for $todayKey');
    // 不 await — 异步执行，不阻塞 brainTick
    kb.diaryStore.summarizeDay(now).then((summary) {
      if (summary != null) {
        PetLogger().info('Overlay', 'dailySummary: generated');
        // 日总结生成后也记入旧 PetDiaryService（UI 兼容）
        PetDiaryService.instance
            .recordEvent('summary', detail: summary.content);
      }
    }).catchError((e) {
      PetLogger().error('Overlay', 'dailySummary failed', e);
    });
  }

  /// 每3小时检查一次是否需要LLM记忆整理
  void _checkMemoryOrganize(DateTime now) {
    // 节流：每3小时最多检查一次
    if (_lastOrganizeCheck != null &&
        now.difference(_lastOrganizeCheck!).inHours < 3) {
      return;
    }
    _lastOrganizeCheck = now;

    final ms = _knowledgeBase?.memoryStore;
    if (ms == null) return;

    // organizeIfNeeded 内部有3天冷却检查 + 预算门控
    ms.organizeIfNeeded().then((_) {
      PetLogger().trace('Overlay', 'memoryOrganize: check done');
    }).catchError((e) {
      PetLogger().error('Overlay', 'memoryOrganize failed', e);
    });
  }

  /// D8f: 智能时段提醒 — 早安/晚安/周末回顾
  void _checkSmartGreeting(DateTime now) {
    final todayKey = '${now.year}-${now.month}-${now.day}';
    if (_lastGreetingDateKey == todayKey) return;
    if (_bubbleShowing) return;
    final idleSecs = now.difference(_lastInteractionAt).inSeconds;
    if (idleSecs < 60) return; // 刚互动过，不打扰

    final weekday = now.weekday;
    final hour = now.hour;
    final isWeekend = weekday == DateTime.saturday || weekday == DateTime.sunday;

    // 早安：6-9点，周末推迟到9-11点
    if ((!isWeekend && hour >= 6 && hour < 9) || (isWeekend && hour >= 9 && hour < 11)) {
      final msg = isWeekend
          ? '周末早安！今天好好休息喵~ ☀️'
          : '早上好！新的一天开始了，加油喵~ ☀️';
      _showChatBubble(msg, duration: const Duration(seconds: 5));
      _lastGreetingDateKey = todayKey;
      _recordDiary('suggestion', detail: msg);
      PetLogger().info('Overlay', 'smartGreeting: morning');
    }
    // 晚安：21-23点
    else if (hour >= 21 && hour < 23) {
      const msg = '晚上好~ 今天辛苦啦，记得早点休息喵~ 🌙';
      _showChatBubble(msg, duration: const Duration(seconds: 5));
      _lastGreetingDateKey = todayKey;
      _recordDiary('suggestion', detail: msg);
      PetLogger().info('Overlay', 'smartGreeting: evening');
    }
    // 周日回顾：15-17点
    else if (weekday == DateTime.sunday && hour >= 15 && hour < 17) {
      _showChatBubble('周末快结束了~ 要不要回顾一下这周和$petSelfRef的互动？去日记页看看AI总结吧~ 📝',
          duration: const Duration(seconds: 6));
      _lastGreetingDateKey = todayKey;
      PetLogger().info('Overlay', 'smartGreeting: weekend recap');
    }
  }

  /// D8f: 空闲过长提醒 — idle >3h 且距上次提醒 >2h
  void _checkIdleReminder(DateTime now) {
    const idleThreshold = Duration(hours: 3);
    const cooldown = Duration(hours: 2);

    final idleSecs = now.difference(_lastInteractionAt).inSeconds;
    if (idleSecs < idleThreshold.inSeconds) return;
    if (_lastIdleReminderAt != null &&
        now.difference(_lastIdleReminderAt!) < cooldown) {
      return;
    }

    _lastIdleReminderAt = now;
    final hours = idleSecs ~/ 3600;
    _showBubbleWithDismiss(
      '主人已经$hours小时没陪$petSelfRef了...记得休息一下哦~ 🥺',
      duration: const Duration(seconds: 4),
    );
    _recordDiary('suggestion',
        detail: '空闲提醒：主人已${hours}h无互动');
    PetLogger().info('Overlay', 'idleReminder: ${hours}h');
  }

  void _recordDiary(String type, {String? detail}) {
    try {
      // 新系统：DiaryStore（规则高亮 + 自动提取记忆）
      _knowledgeBase?.diaryStore.recordEvent(type, detail: detail);
      // 旧系统兼容：UI 目前仍从 PetDiaryService 读取
      PetDiaryService.instance.recordEvent(type, detail: detail);
    } catch (e) {
      PetLogger().error('Overlay', '_recordDiary failed', e);
    }
  }

  /// 通知主应用导航到宠物中心
  void _navigateToPetCenter() {
    const MethodChannel('com.example.deepseek_chat/pet_agent_bridge')
        .invokeMethod('navigate', {'screen': 'pet_center'});
  }

  /// 通知主应用导航到宠物日记
  void _navigateToPetDiary() {
    const MethodChannel('com.example.deepseek_chat/pet_agent_bridge')
        .invokeMethod('navigate', {'screen': 'pet_diary'});
  }
}
