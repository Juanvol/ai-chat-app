// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../config/theme.dart';
import '../services/pet/pet_logger.dart';
import '../utils/page_routes.dart' show pushElastic;
import '../screens/settings_screen.dart';

class HomeWelcome extends StatelessWidget {
  final void Function(String prompt) onTap;

  const HomeWelcome({super.key, required this.onTap});

  Future<bool> _hasApiKey() async {
    try {
      final box = await Hive.openBox('settings');
      final deepseek = box.get('deepseek_key') as String?;
      final generic = box.get('api_key') as String?;
      return (deepseek != null && deepseek.isNotEmpty) || (generic != null && generic.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qs = [
      '写一个快速排序算法',
      '帮我写一封商务邮件',
      '推荐 5 本经典小说',
      '解释相对论的基本原理',
    ];
    return FutureBuilder<bool>(
      future: _hasApiKey(),
      builder: (_, snap) {
        final hasKey = snap.data ?? true; // 加载中不显示警告
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: C.s32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 48),
              // API Key 未配置提示
              if (snap.connectionState == ConnectionState.done && !hasKey)
                Container(
                  margin: const EdgeInsets.only(bottom: C.s16),
                  padding: const EdgeInsets.all(C.s16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(20),
                    borderRadius: BorderRadius.circular(C.r12),
                    border: Border.all(color: Colors.amber.withAlpha(100)),
                  ),
                  child: Column(
                    children: [
                      Row(children: [
                        const Icon(Icons.key, size: 18, color: Colors.amber),
                        const SizedBox(width: C.s8),
                        Text('请先配置 API Key', style: C.title(context).copyWith(color: Colors.amber.shade700)),
                      ]),
                      const SizedBox(height: C.s8),
                      Text('在设置中填入 DeepSeek API Key 后即可开始对话', style: C.caption(context).copyWith(color: Colors.amber.shade700)),
                      const SizedBox(height: C.s12),
                      OutlinedButton.icon(
                        onPressed: () => pushElastic(context, const SettingsScreen()),
                        icon: const Icon(Icons.settings, size: 16),
                        label: const Text('前往设置'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.amber.shade700),
                      ),
                    ],
                  ),
                ),
              Container(
                width: 56, height: 56,
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
                      padding: const EdgeInsets.symmetric(horizontal: C.s16, vertical: C.s12),
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
      },
    );
  }
}
