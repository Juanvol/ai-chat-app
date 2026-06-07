// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../pet/pet_controller.dart';
import '../../services/pet/pet_overlay_host.dart';

/// 宠物头部卡片 — 精简版：猫 emoji + 名字 + 心情 + 好感
class PetHeroCard extends StatelessWidget {
  const PetHeroCard({super.key});

  String get _petName {
    final n = petOverlayController.personaStore?.persona.name;
    return (n != null && n.isNotEmpty) ? n : '糯糯';
  }
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
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  // 左侧：猫 emoji
                  const Text('🐱', style: TextStyle(fontSize: 36)),
                  const SizedBox(width: 10),
                  // 名字 + 等级 + 陪伴天数
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Text(_petName,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                                color: const Color(0xFFB8935D), borderRadius: BorderRadius.circular(10)),
                            child: Text(_levelName(s.totalInteractions),
                                style: const TextStyle(color: Colors.white, fontSize: 10)),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text('${_stageName(s.totalInteractions)} · $moodEmoji 心情${s.mood.toStringAsFixed(0)}',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  // 右侧：好感度
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('❤️', style: TextStyle(fontSize: 18)),
                      Text('${(s.affection / 10).clamp(0, 100).toInt()}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                      Text('好感', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
