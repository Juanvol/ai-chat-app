// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';

class PetSuggestion extends StatelessWidget {
  final String text;
  final VoidCallback onChat;
  final VoidCallback onDismiss;

  const PetSuggestion({
    super.key,
    required this.text,
    required this.onChat,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onChat,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.primary.withAlpha(40)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionChip(label: '聊聊', onTap: onChat, isPrimary: true),
                const SizedBox(width: 8),
                _ActionChip(label: '忽略', onTap: onDismiss, isPrimary: false),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ActionChip({required this.label, required this.onTap, required this.isPrimary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isPrimary ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isPrimary ? scheme.onPrimary : scheme.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
