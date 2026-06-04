// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import '../../pet/pet_controller.dart';
import '../../models/pet_state.dart';
import './pet_service.dart';
import './pet_ai_service.dart';
import './pet_diary_service.dart';
import './pet_logger.dart';
import 'pet_brain.dart';
import 'pet_bubble_manager.dart';
import 'pet_agent_core.dart';

/// 全局宠物浮窗控制器
final petOverlayController = PetOverlayController();

class PetOverlayController {
  static const _overlay = MethodChannel('com.example.deepseek_chat/pet_overlay');

  PetController? _controller;
  PetAiService? _aiService;
  // ignore: unused_field — write-only state tracker
  String? _suggestion;
  // ignore: unused_field — write-only state tracker
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
              // 单击 → 聊天（由 Kotlin 侧弹出 Dialog，Dart 侧记录交互）
              _rhythm.recordInteraction();
              _idleSeconds = 0;
              _recordDiary('tap');
            case 'pet':
              // 双击 → 抚摸
              _rhythm.recordInteraction();
              _idleSeconds = 0;
              if (_controller != null) {
                _controller!.pet();  // 好感+心情
                _cmd('playAnim', {'anim': 'jump'});
                _showBubbleWithDismiss('好开心~ 💕');
                _recordDiary('pet');
              }
            case 'feed':
              // 快捷菜单 → 喂食
              _rhythm.recordInteraction();
              _idleSeconds = 0;
              if (_controller != null) {
                _controller!.feed();
                _cmd('playAnim', {'anim': 'talking'});
                Future.delayed(const Duration(seconds: 2), () => _syncAnim());
                _recordDiary('feed');
              }
            case 'play':
              // 快捷菜单 → 玩耍
              _rhythm.recordInteraction();
              _idleSeconds = 0;
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
    _started = true;
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

  /// Wire 2: 根据 Controller 当前状态同步原生动画 + 气泡
  void _syncAnim() {
    if (!_started) { PetLogger().warn('Overlay', '_syncAnim SKIP: not started'); return; }
    if (_controller == null) { PetLogger().warn('Overlay', '_syncAnim SKIP: controller is null'); return; }
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

  void _syncScale() {
    if (!_started) { PetLogger().warn('Overlay', '_syncScale SKIP: not started'); return; }
    PetService.loadConfig().then((config) {
      final scale = config.petScale;
      const baseSize = 120.0;
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
