// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pet/pet_controller.dart';

class PetHeroCard extends StatelessWidget {
  const PetHeroCard({super.key});

  String _stageName(int interactions) =>
      interactions < 30 ? '初识' : interactions < 200 ? '熟悉' : interactions < 1000 ? '默契' : '老友';
  String _levelName(int interactions) =>
      interactions < 30 ? 'Lv.1' : interactions < 200 ? 'Lv.2' : 'Lv.3';

  @override
  Widget build(BuildContext context) {
    return Consumer<PetController>(
      builder: (context, ctrl, _) {
        final s = ctrl.state;
        final moodEmoji = s.mood > 60 ? '😊' : s.mood > 30 ? '😐' : '😞';
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              children: [
                const Text('🐱', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('弗糯糯',
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.deepPurple.shade400,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(_levelName(s.totalInteractions),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(moodEmoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 4),
                    Text(
                      '${_stageName(s.totalInteractions)} · 陪伴第 ${(s.totalInteractions / 3).ceil()} 天',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
