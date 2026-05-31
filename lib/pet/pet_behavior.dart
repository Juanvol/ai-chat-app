// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class PetBehavior extends StatefulWidget {
  final Widget child;
  final bool ecoMode;

  const PetBehavior({super.key, required this.child, this.ecoMode = false});

  @override
  State<PetBehavior> createState() => PetBehaviorState();
}

class PetBehaviorState extends State<PetBehavior> {
  String? _currentBubble;
  Timer? _idleBubbleScheduler;
  Timer? _bubbleDismissTimer;
  bool _flipped = false;
  Timer? _moveTimer;
  Timer? _actionWatcher;
  final _rng = Random();

  static const List<String> presetBubbles = [
    '主人~',
    '今天天气不错喵~',
    '好无聊...',
    '抱抱~',
    '糯糯在想你呢...',
    '主人在干嘛喵？',
    '有点饿了喵~ 🍖',
    '想睡觉了... 💤',
    '今天真开心！✨',
    '主人在忙吗？',
    '戳戳我试试喵~',
    '糯糯最喜欢主人了~',
    '嗯？有东西在动？',
    '今天有什么好玩的喵？',
    '呼噜呼噜...',
    '主人辛苦了~ ☕',
    '看到主人就开心~ 😸',
    '糯糯会一直陪着你的~',
    '今天学习了新东西！',
    '想要被摸摸头...',
    '喵？那是啥？',
    '主人笑起来最好看了~',
    '不要走嘛...',
    '夜深了，早点休息喵~ 🌙',
    '早安！新的一天！☀️',
    '该吃饭了喵~',
    '糯糯做了个梦...',
    '今天想和主人聊天~',
    '打开看看有什么好玩的？',
    '糯糯在这里等你~',
    '下雨天最适合窝在一起了~',
    '主人的声音真好听~',
    '喵~抓到你了！',
    '糯糯今天心情很好呢~',
    '有点困，但不想睡...',
    '主人的朋友圈更新了！',
    '记得喝水哦~ 💧',
    '工作久了要休息一下~',
    '糯糯给你加油！💪',
    '想到一个好主意！',
  ];

  @override
  void initState() {
    super.initState();
    if (!widget.ecoMode) {
      _startIdleBehavior();
      _startActionWatcher();
    }
  }

  void _startIdleBehavior() {
    _scheduleMove();
    _scheduleBubble();
  }

  void _scheduleBubble() {
    _idleBubbleScheduler?.cancel();
    final delay = Duration(seconds: 60 + _rng.nextInt(60));
    _idleBubbleScheduler = Timer(delay, () {
      if (!mounted || widget.ecoMode) return;
      final text = presetBubbles[_rng.nextInt(presetBubbles.length)];
      showBubble(text);
      _scheduleBubble();
    });
  }

  void _scheduleMove() {
    _moveTimer?.cancel();
    final delay = Duration(seconds: 30 + _rng.nextInt(30));
    _moveTimer = Timer(delay, () {
      if (!mounted || widget.ecoMode) return;
      _flipped = !_flipped;
      if (mounted) setState(() {});
      _scheduleMove();
    });
  }

  void _startActionWatcher() {
    _actionWatcher?.cancel();
    _actionWatcher = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || widget.ecoMode) return;
      try {
        final box = await Hive.openBox('agent_action');
        if (!mounted) return;
        final raw = box.get('current');
        if (raw == null) return;
        final action = Map<String, dynamic>.from(raw as Map);
        final type = action['type'] as String?;
        final content = action['content'] as String?;
        switch (type) {
          case 'bubble':
          case 'speak':
            showBubble(content);
          case 'flip':
            setState(() => _flipped = !_flipped);
        }
      } catch (_) {}
    });
  }

  void showBubble(String? text) {
    if (text == null || text.isEmpty) return;
    _bubbleDismissTimer?.cancel();
    _currentBubble = text;
    if (mounted) setState(() {});
    _bubbleDismissTimer = Timer(const Duration(seconds: 4), () {
      _currentBubble = null;
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(PetBehavior oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ecoMode && !oldWidget.ecoMode) {
      _moveTimer?.cancel();
      _actionWatcher?.cancel();
      _idleBubbleScheduler?.cancel();
      _bubbleDismissTimer?.cancel();
    } else if (!widget.ecoMode && oldWidget.ecoMode) {
      _startIdleBehavior();
      _startActionWatcher();
    }
  }

  @override
  void dispose() {
    _idleBubbleScheduler?.cancel();
    _bubbleDismissTimer?.cancel();
    _moveTimer?.cancel();
    _actionWatcher?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.child;
    if (_flipped) {
      child = Transform.flip(flipX: true, child: child);
    }
    if (_currentBubble != null) {
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: -40,
            left: 0,
            right: 0,
            child: _Bubble(text: _currentBubble!),
          ),
        ],
      );
    }
    return child;
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  const _Bubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.black87, fontSize: 12),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
