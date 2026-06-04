// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/pet/pet_logger.dart';

class HomeWelcome extends StatelessWidget {
  final void Function(String prompt) onTap;

  const HomeWelcome({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qs = [
      '写一个快速排序算法',
      '帮我写一封商务邮件',
      '推荐 5 本经典小说',
      '解释相对论的基本原理',
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: C.s32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 64),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(C.r16),
              color: cs.primaryContainer,
            ),
            child: Icon(Icons.auto_awesome, size: 24, color: cs.primary),
          ),
          const SizedBox(height: C.s20),
          Text('AI 助手', style: C.h1(context)),
          const SizedBox(height: C.s8),
          Text('选择任意模型，即刻开始对话', style: C.caption(context)),
          const SizedBox(height: C.s32),
          ...qs.map((q) => GestureDetector(
                onTap: () {
                  PetLogger().info('Home', 'welcome suggestion: $q');
                  onTap(q);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: C.s8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: C.s16, vertical: C.s12),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(C.r12),
                    border: Border.all(color: cs.outline),
                  ),
                  child: Row(children: [
                    Icon(Icons.lightbulb_outline, size: 15, color: cs.primary),
                    const SizedBox(width: C.s12),
                    Expanded(child: Text(q, style: C.body(context))),
                  ]),
                ),
              )),
        ]),
      ),
    );
  }
}
