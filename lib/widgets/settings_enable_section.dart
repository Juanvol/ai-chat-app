// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../pet/pet_config.dart';

class SettingsEnableSection extends StatelessWidget {
  final bool enabled;
  final AiFrequency frequency;
  final Set<TriggerScene> scenes;
  final ValueChanged<bool> onToggle;
  final ValueChanged<AiFrequency> onFrequencyChanged;
  final ValueChanged<Set<TriggerScene>> onScenesChanged;

  const SettingsEnableSection({
    super.key,
    required this.enabled,
    required this.frequency,
    required this.scenes,
    required this.onToggle,
    required this.onFrequencyChanged,
    required this.onScenesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
          title: const Text('启用悬浮宠物'),
          subtitle: const Text('在屏幕上显示弗糯糯浮窗'),
          value: enabled,
          onChanged: onToggle),
      if (enabled) ...[
        const Padding(
            padding: EdgeInsets.only(left: 16),
            child: Text('AI 主动建议频率',
                style: TextStyle(fontWeight: FontWeight.w500))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<AiFrequency>(
            segments: const [
              ButtonSegment(value: AiFrequency.silent, label: Text('安静')),
              ButtonSegment(
                  value: AiFrequency.occasional, label: Text('偶尔')),
              ButtonSegment(value: AiFrequency.chatty, label: Text('话多')),
            ],
            selected: {frequency},
            onSelectionChanged: (v) => onFrequencyChanged(v.first),
          ),
        ),
        const Padding(
            padding: EdgeInsets.only(left: 16),
            child:
                Text('触发场景', style: TextStyle(fontWeight: FontWeight.w500))),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
              spacing: 8,
              children: TriggerScene.values
                  .map((s) => FilterChip(
                        label: Text(_sceneLabel(s)),
                        selected: scenes.contains(s),
                        onSelected: (v) {
                          final updated = Set<TriggerScene>.from(scenes);
                          v ? updated.add(s) : updated.remove(s);
                          onScenesChanged(updated);
                        },
                      ))
                  .toList()),
        ),
      ],
    ]);
  }

  String _sceneLabel(TriggerScene s) => switch (s) {
        TriggerScene.browser => '浏览器',
        TriggerScene.document => '文档',
        TriggerScene.settings => '设置',
        TriggerScene.all => '全部',
      };
}
