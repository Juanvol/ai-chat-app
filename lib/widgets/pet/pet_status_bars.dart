// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pet/pet_controller.dart';

class PetStatusBars extends StatelessWidget {
  const PetStatusBars({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PetController>(
      builder: (context, ctrl, _) {
        final s = ctrl.state;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Row(children: [
                _Bar(
                    emoji: '🍖',
                    label: '饥饿',
                    value: s.hunger,
                    color: const Color(0xFF4ECCA3)),
                const SizedBox(width: 8),
                _Bar(
                    emoji: '😊',
                    label: '心情',
                    value: s.mood.toInt(),
                    color: const Color(0xFFE94560)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                _Bar(
                    emoji: '⚡',
                    label: '体力',
                    value: s.energy,
                    color: const Color(0xFFFFC107)),
                const SizedBox(width: 8),
                _Bar(
                    emoji: '❤️',
                    label: '好感',
                    value: (s.affection / 10).clamp(0, 100).toInt(),
                    color: const Color(0xFFFF6B9D)),
              ]),
            ],
          ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  final String emoji, label;
  final int value;
  final Color color;
  const _Bar(
      {required this.emoji,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 12)),
                const Spacer(),
                Text(value.toString(),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: value / 100,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade800,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
