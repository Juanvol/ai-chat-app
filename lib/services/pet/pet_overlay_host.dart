// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import '../pet/pet_controller.dart';
import '../pet/pet_state.dart';
import '../services/pet_service.dart';
import '../services/pet_ai_service.dart';
import '../services/pet_diary_service.dart';
import '../services/pet_logger.dart';
import 'pet_brain.dart';
import 'pet_bubble_manager.dart';
import 'pet_agent_core.dart';

/// 全局宠物浮窗控制器
final petOverlayController = PetOverlayController();

class PetOverlayController {
  static const _overlay = MethodChannel('com.example.deepseek_chat/pet_overlay');
  static const _petSvc = MethodChannel('com.example.deepseek_chat/pet_service');

  PetController? _controller;
  PetAiService? _aiService;
  String? _suggestion;
  bool _screenOn = true;
  int _batteryLevel = 100;
  bool _charging = false;
  bool _started = false;

  // PetBrain 行为决策
  final _brain = BehaviorWeights();
  final _bubbleMgr = PetBubbleManager();
  final _pokeTracker = PokeTracker();
  final _rhythm = UserRhythm();
  final _dailyMood = DailyMood.today();
  Timer? _brainTimer;
  int _idleSeconds = 0;
  Timer? _idleSecondTimer;

  // 兼容旧代码
  final _rng = Random();
  bool _bubbleShowing = false;

  bool get isActive => _started;

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
              _rhythm.recordInteraction();
              _idleSeconds = 0;
              final poke = _pokeTracker.recordPoke();
              if (_controller == null) {
                PetLogger().warn('Overlay', 'tap IGNORED: controller is null (pet not started?)');
              } else {
                _controller!.chat();
                _cmd('playAnim', {'anim': 'talking'});
                final b = _onPoke(poke);
                _cmd('showBubble', {'text': b, 'durationMs': 3000});
                _recordDiary('tap', detail: poke.name);
                Future.delayed(const Duration(seconds: 3), () => _syncAnim());
              }
            case 'longPress':
              _rhythm.recordInteraction();
              _idleSeconds = 0;
              if (_controller == null) {
                PetLogger().warn('Overlay', 'longPress IGNORED: controller is null');
              } else {
                _controller!.feed();
                _cmd('playAnim', {'anim': 'hungry'});
                final eatBubbles = ['好吃好吃~ 😋', '谢谢主人！', '再来一份~', '好幸福喵~', '吃饱了！'];
                _showBubbleWithDismiss(eatBubbles[_rng.nextInt(eatBubbles.length)]);
                _recordDiary('longPress');
                Future.delayed(const Duration(seconds: 2), () => _syncAnim());
              }
            case 'screen':
              if (x == -1) {
                _screenOn = false;
                _cmd('playAnim', {'anim': 'sleeping'});
              } else {
                _screenOn = true;
                _syncAnim();
              }
            case 'battery':
              _batteryLevel = x.toInt();
              _charging = y == 1;
              if (_batteryLevel < 15 && !_charging && !_bubbleShowing) {
                _showBubbleWithDismiss('好困…电量不足了💤', duration: const Duration(seconds: 5));
              }
          }
      }
    });
  }

  Future<void> start() async {
    if (_started) { PetLogger().warn('Overlay', 'start SKIP: already started'); return; }
    _started = true;
    PetLogger().info('Overlay', 'start() BEGIN');

    PetState saved = PetState();
    try { saved = await PetService.loadState(); } catch (e) { PetLogger().error('Overlay', 'loadState failed', e); }

    _controller = PetController(
      initialState: saved,
      onStateChanged: (s) {
        try { PetService.saveState(s); } catch (e) { PetLogger().error('Overlay', 'saveState failed', e); }
        _syncState();
      },
    );
    _controller!.start();

    _aiService = PetAiService();
    await _aiService!.init();
    _aiService!.startProactiveTimer((s) {
      _suggestion = s;
      _recordDiary('suggestion', detail: s);
      _showBubbleWithDismiss(s, duration: const Duration(seconds: 5));
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      _syncAnim();
      _syncScale();
    });
    _startBrainLoop();
    _scheduleIdleSecond();
    PetLogger().info('Overlay', 'start done (PetBrain v2)');
  }

  Future<void> stop() async {
    _stopBrainLoop();
    _started = false;
    _aiService?.dispose();
    _aiService = null;
    if (_controller != null) {
      try { PetService.saveState(_controller!.state); } catch (e) { PetLogger().error('Overlay', 'stop saveState failed', e); }
      _controller!.dispose();
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
    _brainTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_started) return;
      _brainTick();
    });
  }

  void _scheduleIdleSecond() {
    _idleSecondTimer?.cancel();
    _idleSecondTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_started) _idleSeconds++;
    });
  }

  void _stopBrainLoop() {
    _brainTimer?.cancel();
    _brainTimer = null;
    _idleSecondTimer?.cancel();
    _idleSecondTimer = null;
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

  /// 戳宠反应映射
  String _onPoke(PokeReaction poke) {
    switch (poke) {
      case PokeReaction.playDead:
        _cmd('playAnim', {'anim': 'sleeping'});
        Future.delayed(const Duration(seconds: 3), () => _syncAnim());
        return '啊！主人你太用力了喵...（装死）💀';
      case PokeReaction.annoyed:
        _cmd('playAnim', {'anim': 'idle', 'emotionSpeed': 2.0});
        final b = _bubbleMgr.pick(category: 'poke', period: DayPeriodExt.fromHour(DateTime.now().hour));
        Future.delayed(const Duration(seconds: 2), () => _syncAnim());
        return b ?? '别戳了喵~';
      case PokeReaction.bounce:
        return _bubbleMgr.pick(category: 'poke', period: DayPeriodExt.fromHour(DateTime.now().hour)) ?? '喵~';
      case PokeReaction.none:
        return '嗯？';
    }
  }

  void _brainTick() {
    final now = DateTime.now();
    final s = _controller?.state;
    final al = PetAgentCore.shared?.attentionLevel ?? AttentionLevel.L3;

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

    // 空闲分层
    final tier = IdleTierExt.fromIdleSeconds(_idleSeconds);

    final action = _brain.pickAction();
    PetLogger().trace('Overlay', 'brainTick: $action tier=${tier.name} idle=${_idleSeconds}s');

    switch (action) {
      case 'wander':
        final rng = Random();
        // 随机目标（需要在 PetView 初始化后由物理引擎的边界限制）
        final tx = rng.nextDouble() * 800 + 50;
        final ty = rng.nextDouble() * 1000 + 200;
        _cmd('moveTo', {'x': tx, 'y': ty, 'speed': 150});
        _cmd('playAnim', {'anim': 'idle'}); // 走动画尚未生成，用 idle 代替

      case 'sitDown':
        _cmd('playAnim', {'anim': 'sleeping'}); // sit 帧未生成，用 sleeping 代替
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
    if (!_started) { PetLogger().warn('Overlay', '_syncState SKIP: not started'); return; }
    if (_controller == null) { PetLogger().warn('Overlay', '_syncState SKIP: controller is null'); return; }
    final s = _controller!.state;
    PetLogger().info('Overlay', 'sync: status=${s.status.name} hunger=${s.hunger} mood=${s.mood.toStringAsFixed(0)} energy=${s.energy} affection=${s.affection}');
    _syncAnim();

    final emoji = switch (s.status) {
      PetStatus.hungry => '🍖',
      PetStatus.eating => '😋',
      PetStatus.happy => '😸',
      PetStatus.sleepy || PetStatus.sleeping => '💤',
      PetStatus.talking => '💬',
      PetStatus.idle => s.mood > 60 ? '😊' : s.mood > 30 ? '😐' : '😞',
    };
    _cmd('showEmoji', {'emoji': emoji});
  }

  void _syncAnim() {
    if (!_started) { PetLogger().warn('Overlay', '_syncAnim SKIP: not started'); return; }
    if (_controller == null) { PetLogger().warn('Overlay', '_syncAnim SKIP: controller is null'); return; }
    final s = _controller!.state;
    final anim = switch (s.status) {
      PetStatus.hungry || PetStatus.eating => 'hungry',
      PetStatus.sleepy || PetStatus.sleeping => 'sleeping',
      PetStatus.talking => 'talking',
      _ => 'idle',
    };
    PetLogger().info('Overlay', 'anim sync: ${s.status.name} → $anim');
    _cmd('playAnim', {'anim': anim});
  }

  /// 供外部调用（如设置页修改大小后即时生效）
  void syncScale() => _syncScale();

  void _syncScale() {
    if (!_started) { PetLogger().warn('Overlay', '_syncScale SKIP: not started'); return; }
    PetService.loadConfig().then((config) {
      final scale = config.petScale;
      final baseSize = 120.0;
      final w = (baseSize * scale).round();
      final h = (baseSize * scale).round();
      PetLogger().info('Overlay', 'scale sync: ${scale.toStringAsFixed(1)} → ${w}x${h}dp');
      _cmd('setSize', {'width': w, 'height': h});
    }).catchError((e) {
      PetLogger().error('Overlay', '_syncScale failed', e);
    });
  }

  void _cmd(String cmd, [Map<String, dynamic>? args]) {
    PetLogger().trace('Overlay', 'cmd: $cmd ${args?.toString() ?? ""}');
    try {
      _overlay.invokeMethod('cmd', {'cmd': cmd, 'args': args});
    } catch (e) {
      PetLogger().error('Overlay', 'cmd $cmd failed (channel not ready?)', e);
    }
  }

  void _recordDiary(String type, {String? detail}) {
    try {
      // fire-and-forget，不阻塞触控响应
      PetDiaryService().recordEvent(type, detail: detail);
    } catch (e) {
      PetLogger().error('Overlay', '_recordDiary failed', e);
    }
  }
}
