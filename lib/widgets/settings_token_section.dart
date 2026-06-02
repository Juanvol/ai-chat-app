// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';

class SettingsTokenSection extends StatelessWidget {
  final int? budget;
  final TextEditingController customController;
  final ValueChanged<int?> onBudgetSelected;
  final VoidCallback onCustomSaved;

  const SettingsTokenSection({
    super.key,
    required this.budget,
    required this.customController,
    required this.onBudgetSelected,
    required this.onCustomSaved,
  });

  static const _presets = [10000, 30000, 50000, 100000, null];

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('💰 Token 预算（每日）',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: _presets.map((v) {
          final label = v == null ? '不限制' : '${(v / 1000).round()}k';
          final isSelected = budget == v;
          return ChoiceChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (_) => onBudgetSelected(v),
          );
        }).toList(),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: TextField(
            controller: customController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: '自定义额度', hintText: '如 20000', isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(onPressed: onCustomSaved, child: const Text('保存')),
      ]),
      const SizedBox(height: 4),
      Text('超出额度后 Agent 暂停 LLM 调用，仅响应规则',
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withOpacity(0.6))),
    ]);
  }
}
