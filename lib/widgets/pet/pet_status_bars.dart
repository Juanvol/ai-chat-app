// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../pet/pet_controller.dart';

/// 宠物状态条 — 精简版：4 个迷你进度条一行
class PetStatusBars extends StatelessWidget {
  const PetStatusBars({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PetController>(
      builder: (context, ctrl, _) {
        final s = ctrl.state;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(child: _MiniBar(emoji: '🍖', value: s.hunger, color: const Color(0xFF4ECCA3), alert: s.hunger < 30)),
              const SizedBox(width: 4),
              Expanded(child: _MiniBar(emoji: '😊', value: s.mood.toInt(), color: const Color(0xFFE94560), alert: s.mood < 30)),
              const SizedBox(width: 4),
              Expanded(child: _MiniBar(emoji: '⚡', value: s.energy, color: const Color(0xFFFFC107), alert: s.energy < 20)),
              const SizedBox(width: 4),
              Expanded(child: _MiniBar(emoji: '❤️', value: (s.affection / 10).clamp(0, 100).toInt(), color: const Color(0xFFFF6B9D))),
            ],
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .slideY(begin: -0.2, end: 0, duration: 400.ms, curve: Curves.easeOut),
        );
      },
    );
  }
}

class _MiniBar extends StatelessWidget {
  final String emoji;
  final int value;
  final Color color;
  final bool alert;
  const _MiniBar({required this.emoji, required this.value, required this.color, this.alert = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 2),
          Text('$value', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ]),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value / 100),
            duration: 600.ms,
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(alert ? Colors.red.shade400 : color),
            ),
          ),
        ),
      ],
    );
  }
}
