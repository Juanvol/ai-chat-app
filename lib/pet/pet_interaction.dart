// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PetInteraction extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDragEnd;

  static const _channel = MethodChannel('com.example.deepseek_chat/pet_window');

  const PetInteraction({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onDragEnd,
  });

  Future<void> _onPanUpdate(DragUpdateDetails details, BuildContext context) async {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    try {
      await _channel.invokeMethod('moveWindow', {
        'dx': (details.delta.dx * ratio).round(),
        'dy': (details.delta.dy * ratio).round(),
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      onPanUpdate: (d) => _onPanUpdate(d, context),
      onPanEnd: (_) => onDragEnd?.call(),
      child: child,
    );
  }
}
