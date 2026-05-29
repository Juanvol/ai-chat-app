// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'pet_state.dart';

class PetRenderer extends StatefulWidget {
  final PetStatus status;
  final double size;

  const PetRenderer({
    super.key,
    required this.status,
    this.size = 120,
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
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant PetRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _loadFrames();
      _ac.duration = Duration(milliseconds: _frames.length * 80);
      _ac.forward(from: 0);
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
    return AnimatedBuilder(
      animation: _ac,
      builder: (context, child) {
        if (_frames.isEmpty) return SizedBox(width: widget.size, height: widget.size);
        final idx = (_ac.value * _frames.length).floor().clamp(0, _frames.length - 1);
        return Image(
          image: _frames[idx],
          width: widget.size,
          height: widget.size,
          errorBuilder: (_, __, ___) => SizedBox(width: widget.size, height: widget.size),
        );
      },
    );
  }
}
