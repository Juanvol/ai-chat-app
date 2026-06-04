// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pet/pet_controller.dart';

class PetActionBar extends StatelessWidget {
  final VoidCallback? onChat;

  const PetActionBar({super.key, this.onChat});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<PetController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Btn(icon: '🍖', label: '喂食', onTap: ctrl.feed),
          _Btn(icon: '🎾', label: '玩耍', onTap: ctrl.play),
          _Btn(icon: '💤', label: '哄睡', onTap: () => ctrl.sleep()),
          _Btn(icon: '💬', label: '聊天', onTap: onChat ?? () {}),
          _Btn(icon: '✋', label: '摸摸', onTap: ctrl.pet),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final String icon, label;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
