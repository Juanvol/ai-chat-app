// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../pet/pet_config.dart';
import '../pet/pet_persona.dart';
import '../services/pet_service.dart';
import '../services/pet_token_service.dart';

class PetSettingsScreen extends StatefulWidget {
  const PetSettingsScreen({super.key});

  @override
  State<PetSettingsScreen> createState() => _PetSettingsScreenState();
}

class _PetSettingsScreenState extends State<PetSettingsScreen> {
  static const _channel = MethodChannel('com.example.deepseek_chat/pet_service');

  PetConfig _config = PetConfig();
  bool _loaded = false;

  // ── 新增：性格/额度/模型/视觉 ──
  PetPersona _persona = PetPersona();
  int? _dailyBudget = 50000;
  String _decisionModel = 'deepseek-chat';
  String _chatModel = 'deepseek-chat';
  bool _visionEnabled = false;

  static const _personaTemplates = {
    'default': ('默认', '软萌粘人，偶尔摆烂'),
    'tsundere': ('傲娇猫', '高冷毒舌，爱答不理'),
    'clingy': ('粘人精', '超级粘人，主人离开就难过'),
    'lazy': ('摆烂王', '能躺着绝不坐着，佛系生活'),
  };

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      _config = await PetService.loadConfig();
    } catch (_) {}
    await _loadPersona();
    await _loadBudget();
    await _loadModelSettings();
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _loadPersona() async {
    try {
      final box = await Hive.openBox('pet_config');
      final raw = box.get('persona');
      if (raw != null) {
        _persona = PetPersona.fromJson(Map<String, dynamic>.from(raw as Map));
      }
    } catch (_) {}
  }

  Future<void> _savePersona(PetPersona p) async {
    _persona = p;
    try {
      final box = await Hive.openBox('pet_config');
      await box.put('persona', p.toJson());
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _loadBudget() async {
    try {
      final svc = PetTokenService();
      _dailyBudget = svc.dailyBudget;
    } catch (_) {}
  }

  Future<void> _saveBudget(int? tokens) async {
    _dailyBudget = tokens;
    try {
      final svc = PetTokenService();
      await svc.setBudget(tokens);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _loadModelSettings() async {
    try {
      final box = await Hive.openBox('pet_config');
      _decisionModel = box.get('decisionModel', defaultValue: 'deepseek-chat') as String;
      _chatModel = box.get('chatModel', defaultValue: 'deepseek-chat') as String;
      _visionEnabled = box.get('visionEnabled', defaultValue: false) as bool;
    } catch (_) {}
  }

  Future<void> _saveModelSetting(String key, dynamic value) async {
    try {
      final box = await Hive.openBox('pet_config');
      await box.put(key, value);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _saveConfig(PetConfig c) async {
    _config = c;
    await PetService.saveConfig(_config);
    if (mounted) setState(() {});
  }

  Future<void> _toggleEnabled(bool enabled) async {
    await _saveConfig(_config.copyWith(enabled: enabled));
    try {
      if (enabled) {
        final granted = await _channel.invokeMethod<bool>('isOverlayPermissionGranted') ?? false;
        if (!granted) {
          await _channel.invokeMethod('requestOverlayPermission');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请授予悬浮窗权限后重新开启')),
            );
          }
          return;
        }
        await _channel.invokeMethod('startPet');
      } else {
        await _channel.invokeMethod('stopPet');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('🐾 弗糯糯设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildEnableSwitch(),
          const Divider(height: 32),
          _buildAiFrequency(),
          const Divider(height: 32),
          _buildTriggerScenes(),
          const Divider(height: 32),
          _buildSkinSelector(),
          const Divider(height: 32),
          _buildScaleSlider(),
          const Divider(height: 32),
          _buildAutoStart(),
          const SizedBox(height: 8),
          _buildQuietHours(),
          const Divider(height: 32),
          _buildPersonaSection(),
          const Divider(height: 32),
          _buildBudgetSection(),
          const Divider(height: 32),
          _buildModelSection(),
          const Divider(height: 32),
          _buildVisionToggle(),
        ],
      ),
    );
  }

  Widget _buildEnableSwitch() {
    return SwitchListTile(
      title: const Text('开启弗糯糯'),
      subtitle: const Text('在任意应用上层显示电子宠物'),
      value: _config.enabled,
      onChanged: _toggleEnabled,
    );
  }

  Widget _buildAiFrequency() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AI 主动建议频率', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        SegmentedButton<AiFrequency>(
          segments: const [
            ButtonSegment(value: AiFrequency.silent, label: Text('安静')),
            ButtonSegment(value: AiFrequency.occasional, label: Text('偶尔')),
            ButtonSegment(value: AiFrequency.chatty, label: Text('话多')),
          ],
          selected: {_config.aiFrequency},
          onSelectionChanged: (s) => _saveConfig(_config.copyWith(aiFrequency: s.first)),
        ),
      ],
    );
  }

  Widget _buildTriggerScenes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('触发场景', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: TriggerScene.values.map((scene) {
            final active = _config.triggerScenes.contains(scene);
            return FilterChip(
              label: Text(_sceneLabel(scene)),
              selected: active,
              onSelected: (_) {
                final scenes = Set<TriggerScene>.from(_config.triggerScenes);
                active ? scenes.remove(scene) : scenes.add(scene);
                _saveConfig(_config.copyWith(triggerScenes: scenes));
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSkinSelector() {
    return ListTile(
      title: const Text('宠物皮肤'),
      subtitle: Text(_config.skinName),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        // 皮肤选择器留待后续实现
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('更多皮肤即将推出')),
        );
      },
    );
  }

  Widget _buildScaleSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('宠物大小: ${_config.petScale.toStringAsFixed(1)}x',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        Slider(
          value: _config.petScale,
          min: 0.5,
          max: 1.5,
          divisions: 10,
          onChanged: (v) => _saveConfig(_config.copyWith(petScale: v)),
        ),
      ],
    );
  }

  Widget _buildAutoStart() {
    return SwitchListTile(
      title: const Text('开机自启'),
      subtitle: const Text('手机重启后自动启动弗糯糯'),
      value: _config.autoStart,
      onChanged: (v) => _saveConfig(_config.copyWith(autoStart: v)),
    );
  }

  Widget _buildQuietHours() {
    return ListTile(
      title: const Text('免打扰'),
      subtitle: Text(_config.quietUntil == null
          ? '未设置'
          : '至 ${_config.quietUntil!.hour}:${_config.quietUntil!.minute.toString().padLeft(2, '0')}'),
      trailing: _config.quietUntil != null
          ? IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => _saveConfig(_config.copyWith(quietUntil: PetConfig.clearSentinel)),
            )
          : null,
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.now(),
        );
        if (time != null) {
          final until = DateTime(
            DateTime.now().year, DateTime.now().month, DateTime.now().day,
            time.hour, time.minute,
          );
          await _saveConfig(_config.copyWith(quietUntil: until));
        }
      },
    );
  }

  // ── 性格设置 ──

  Widget _buildPersonaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('😸 性格设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        // 模板选择
        DropdownButtonFormField<String>(
          initialValue: _persona.templateId ?? 'default',
          decoration: const InputDecoration(
            labelText: '性格模板',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: _personaTemplates.entries.map((e) => DropdownMenuItem(
            value: e.key,
            child: Text('${e.value.$1} — ${e.value.$2}', style: const TextStyle(fontSize: 14)),
          )).toList(),
          onChanged: (v) {
            if (v == null) return;
            final prompts = {
              'default': PetPersona().systemPrompt,
              'tsundere': '你是弗糯糯，一只高冷的傲娇猫。性格：毒舌、爱答不理、偶尔心软。自称"糯糯"，句尾加"喵"或"哼"。保持短小，不超过2句话。',
              'clingy': '你是弗糯糯，一只超级粘人的宠物精灵。性格：粘人、撒娇、离开主人就难过。自称"糯糯"，句尾加"喵~"或"抱抱~"。保持短小可爱，不超过2句话。',
              'lazy': '你是弗糯糯，一只佛系摆烂的宠物精灵。性格：懒散、随缘、能躺着绝不坐着。自称"糯糯"，句尾加"..."或"zzZ"。保持短小，不超过2句话。',
            };
            _savePersona(_persona.copyWith(
              templateId: v,
              systemPrompt: prompts[v] ?? _persona.systemPrompt,
            ));
          },
        ),
        const SizedBox(height: 12),
        // System Prompt 编辑
        TextField(
          controller: TextEditingController(text: _persona.systemPrompt),
          maxLines: 3,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'System Prompt',
            hintText: '描述糯糯的性格、语气、行为规则...',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(12),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) _savePersona(_persona.copyWith(systemPrompt: v.trim()));
          },
        ),
        const SizedBox(height: 4),
        Text('按回车保存', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }

  // ── 每日额度 ──

  Widget _buildBudgetSection() {
    final labels = ['10k', '30k', '50k', '100k', '不限制'];
    final values = <int?>[10000, 30000, 50000, 100000, null];
    final selectedIdx = values.indexOf(_dailyBudget);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('💰 Token 每日额度', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text('超出额度后 Agent 暂停 LLM 调用，仅响应规则', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: List.generate(labels.length, (i) => ChoiceChip(
            label: Text(labels[i]),
            selected: selectedIdx == i,
            onSelected: (_) => _saveBudget(values[i]),
          )),
        ),
      ],
    );
  }

  // ── 模型选择 ──

  Widget _buildModelSection() {
    final models = ['deepseek-chat', 'deepseek-reasoner'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🤖 模型配置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        // 决策模型
        DropdownButtonFormField<String>(
          initialValue: models.contains(_decisionModel) ? _decisionModel : 'deepseek-chat',
          decoration: const InputDecoration(
            labelText: '决策模型（感知→行动）',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: models.map((m) => DropdownMenuItem(
            value: m,
            child: Text(m, style: const TextStyle(fontSize: 14)),
          )).toList(),
          onChanged: (v) {
            if (v != null) {
              _decisionModel = v;
              _saveModelSetting('decisionModel', v);
            }
          },
        ),
        const SizedBox(height: 12),
        // 对话模型
        DropdownButtonFormField<String>(
          initialValue: models.contains(_chatModel) ? _chatModel : 'deepseek-chat',
          decoration: const InputDecoration(
            labelText: '对话模型（聊天回复）',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: models.map((m) => DropdownMenuItem(
            value: m,
            child: Text(m, style: const TextStyle(fontSize: 14)),
          )).toList(),
          onChanged: (v) {
            if (v != null) {
              _chatModel = v;
              _saveModelSetting('chatModel', v);
            }
          },
        ),
      ],
    );
  }

  // ── 视觉开关 ──

  Widget _buildVisionToggle() {
    return SwitchListTile(
      title: const Text('👁️ 视觉分析（MiMo）'),
      subtitle: const Text('允许糯糯分析你的屏幕截图，提供上下文感知建议'),
      value: _visionEnabled,
      onChanged: (v) {
        _visionEnabled = v;
        _saveModelSetting('visionEnabled', v);
      },
    );
  }

  String _sceneLabel(TriggerScene s) => switch (s) {
    TriggerScene.browser => '浏览器',
    TriggerScene.document => '文档',
    TriggerScene.settings => '设置',
    TriggerScene.all => '全部',
  };
}
