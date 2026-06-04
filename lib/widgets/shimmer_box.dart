// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 单行骨架占位条
class ShimmerBox extends StatelessWidget {
  final double width, height;
  final double radius;

  const ShimmerBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(radius),
      ),
    ).animate().shimmer(duration: 1200.ms, color: Colors.grey.shade100);
  }
}

/// 带卡片容器的骨架占位
class ShimmerCard extends StatelessWidget {
  final int lines;
  const ShimmerCard({super.key, this.lines = 3});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ShimmerBox(width: 120, height: 14),
            const SizedBox(height: 12),
            ...List.generate(
              lines,
              (i) => Padding(
                padding: EdgeInsets.only(bottom: i < lines - 1 ? 8 : 0),
                child: ShimmerBox(width: i == lines - 1 ? 150 : double.infinity, height: 12, radius: 3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
