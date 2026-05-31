// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'pet_state.dart';

class PetRenderer extends StatefulWidget {
  final PetStatus status;
  final double size;
  final bool ecoMode;
  final String? moodEmoji;

  const PetRenderer({
    super.key,
    required this.status,
    this.size = 120,
    this.ecoMode = false,
    this.moodEmoji,
  });

  @override
  State<PetRenderer> createState() => _PetRendererState();
}

class _PetRendererState extends State<PetRenderer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  List<AssetImage> _frames = [];

  static const _skinBase = 'assets/pet_skins/funuonuo';
  static const _frameCounts = {
    PetStatus.idle: 54,
    PetStatus.hungry: 63,
    PetStatus.talking: 63,
    PetStatus.sleeping: 17,
  };

  String _resolveDir(PetStatus status) {
    if (_frameCounts.containsKey(status)) return status.name;
    return PetStatus.idle.name;
  }

  int _resolveCount(PetStatus status) {
    return _frameCounts[status] ?? 54;
  }

  @override
  void initState() {
    super.initState();
    _loadFrames();
    _ac = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _frames.length * 80),
    );
    _applyAnimMode();
  }

  @override
  void didUpdateWidget(covariant PetRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _loadFrames();
      _ac.duration = Duration(milliseconds: _frames.length * 80);
      _ac.forward(from: 0);
    }
    if (oldWidget.ecoMode != widget.ecoMode) {
      _applyAnimMode();
      if (!widget.ecoMode) _ac.forward(from: 0);
    }
  }

  void _applyAnimMode() {
    if (widget.ecoMode) {
      _ac.stop();
    } else {
      _ac.repeat();
    }
  }

  void _loadFrames() {
    final dir = _resolveDir(widget.status);
    final count = _resolveCount(widget.status);
    _frames = List.generate(
      count,
      (i) => AssetImage('$_skinBase/$dir/frame_${i.toString().padLeft(2, '0')}.png'),
    );
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final petWidget = ListenableBuilder(
      listenable: _ac,
      builder: (context, child) {
        if (_frames.isEmpty) return SizedBox(width: widget.size, height: widget.size);
        final idx = widget.ecoMode
            ? 0
            : (_ac.value * _frames.length).floor().clamp(0, _frames.length - 1);
        return Image.asset(
          '${_skinBase}/${_resolveDir(widget.status)}/frame_${idx.toString().padLeft(2, '0')}.png',
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            width: widget.size,
            height: widget.size,
            color: const Color(0xFFE0E8F0),
            child: const Center(child: Text('🐾', style: TextStyle(fontSize: 32))),
          ),
        );
      },
    );

    if (widget.moodEmoji == null) return petWidget;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        petWidget,
        Positioned(
          top: -8,
          right: -8,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: Text(
              widget.moodEmoji!,
              key: ValueKey(widget.moodEmoji),
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
      ],
    );
  }
}
