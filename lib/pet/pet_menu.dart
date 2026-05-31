// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';

class PetMenu extends StatelessWidget {
  final VoidCallback? onFeed;
  final VoidCallback? onPlay;
  final VoidCallback? onChat;
  final VoidCallback? onSleep;
  final VoidCallback onDismiss;

  const PetMenu({
    super.key,
    this.onFeed,
    this.onPlay,
    this.onChat,
    this.onSleep,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.transparent,
        child: Stack(
          children: [
            _MenuBubble(
              onFeed: onFeed,
              onPlay: onPlay,
              onChat: onChat,
              onSleep: onSleep,
              onDismiss: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuBubble extends StatelessWidget {
  final VoidCallback? onFeed;
  final VoidCallback? onPlay;
  final VoidCallback? onChat;
  final VoidCallback? onSleep;
  final VoidCallback onDismiss;

  const _MenuBubble({
    this.onFeed,
    this.onPlay,
    this.onChat,
    this.onSleep,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 130,
      left: 0,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xF0212121),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuItem(icon: Icons.restaurant, label: '喂食', onTap: () { onFeed?.call(); onDismiss(); }),
              _MenuItem(icon: Icons.toys, label: '玩耍', onTap: () { onPlay?.call(); onDismiss(); }),
              _MenuItem(icon: Icons.chat_bubble, label: '聊天', onTap: () { onChat?.call(); onDismiss(); }),
              _MenuItem(icon: Icons.bedtime, label: '睡觉', onTap: () { onSleep?.call(); onDismiss(); }),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
