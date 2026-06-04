// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../pet/pet_controller.dart';

class PetActionBar extends StatelessWidget {
  final VoidCallback? onChat;
  const PetActionBar({super.key, this.onChat});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<PetController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Btn(icon: '🍖', label: '喂食', onTap: ctrl.feed)
              .animate().fadeIn(delay: 300.ms, duration: 300.ms).slideY(begin: 0.3, end: 0, delay: 300.ms, duration: 300.ms),
          _Btn(icon: '🎾', label: '玩耍', onTap: ctrl.play)
              .animate().fadeIn(delay: 400.ms, duration: 300.ms).slideY(begin: 0.3, end: 0, delay: 400.ms, duration: 300.ms),
          _Btn(icon: '💤', label: '哄睡', onTap: () => ctrl.sleep())
              .animate().fadeIn(delay: 500.ms, duration: 300.ms).slideY(begin: 0.3, end: 0, delay: 500.ms, duration: 300.ms),
          _Btn(icon: '💬', label: '聊天', onTap: onChat ?? () {})
              .animate().fadeIn(delay: 600.ms, duration: 300.ms).slideY(begin: 0.3, end: 0, delay: 600.ms, duration: 300.ms),
          _Btn(icon: '✋', label: '摸摸', onTap: ctrl.pet)
              .animate().fadeIn(delay: 700.ms, duration: 300.ms).slideY(begin: 0.3, end: 0, delay: 700.ms, duration: 300.ms),
        ],
      ),
    );
  }
}

class _Btn extends StatefulWidget {
  final String icon, label;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.label, required this.onTap});

  @override
  State<_Btn> createState() => _BtnState();
}

class _BtnState extends State<_Btn> {
  double _scale = 1;

  void _onTapDown(_) => setState(() => _scale = 0.85);
  void _onTapUp(_) {
    setState(() => _scale = 1);
    HapticFeedback.lightImpact();
    widget.onTap();
  }
  void _onTapCancel() => setState(() => _scale = 1);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedScale(
        scale: _scale,
        duration: 120.ms,
        curve: Curves.easeOutBack,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 1),
            Text(widget.label, style: const TextStyle(fontSize: 10)),
          ]),
        ),
      ),
    );
  }
}
