// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:share_plus/share_plus.dart';
import '../../pet/pet_config.dart';
import '../../pet/pet_persona.dart';
import '../../services/pet/pet_service.dart';
import '../../services/pet/pet_token_service.dart';
import '../../services/pet/pet_logger.dart';
import '../../services/pet/pet_overlay_host.dart' show petOverlayController;
import '../../widgets/shimmer_box.dart';
import '../../models/model_config.dart';
import '../../config/theme.dart';

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
  PersonalityTraits _traits = PersonalityTraits.balanced;
  late TextEditingController _selfRefCtrl;
  late TextEditingController _endingCtrl;
  int _maxLen = 80;
  late final TextEditingController _promptController = TextEditingController();
  late final TextEditingController _budgetController;
  Timer? _budgetDebounce;
  int? _dailyBudget = 50000;
  // D8: Token 用量统计
  int _todayUsed = 0;
  int _weekUsed = 0;
  int _monthUsed = 0;
  int _chatContextRounds = 3;
  String _decisionModel = 'deepseek-chat';
  String _chatModel = 'deepseek-chat';
  String _visionModel = '';  // 空 = 跟随主模型
  String _visionApiKey = '';
  // ignore: unused_field — 预留，后续支持视觉自定义 Base URL
  String _visionBaseUrl = '';
  late final TextEditingController _visionKeyController;
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
    _budgetController = TextEditingController();
    _visionKeyController = TextEditingController();
    _selfRefCtrl = TextEditingController(text: _persona.style.selfReference);
    _endingCtrl = TextEditingController(text: _persona.style.sentenceEnding);
    _loadConfig();
  }

  @override
  void dispose() {
    _budgetDebounce?.cancel();
    _promptController.dispose();
    _budgetController.dispose();
    _visionKeyController.dispose();
    _selfRefCtrl.dispose();
    _endingCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    PetLogger().info('PetSettings', 'loadConfig()');
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
      _promptController.text = _persona.systemPrompt;
      _selfRefCtrl.text = _persona.style.selfReference;
      _endingCtrl.text = _persona.style.sentenceEnding;
      _maxLen = _persona.style.maxSentenceLength;
      _traits = _persona.personalityTraits;
    } catch (_) {}
  }

  Future<void> _savePersona(PetPersona p) async {
    final updated = p.copyWith(
      systemPrompt: _promptController.text,
      personalityTraits: _traits,
      style: p.style.copyWith(
        selfReference: _selfRefCtrl.text,
        sentenceEnding: _endingCtrl.text,
        maxSentenceLength: _maxLen,
      ),
    );
    _persona = updated;
    _promptController.text = updated.systemPrompt;
    try {
      final box = await Hive.openBox('pet_config');
      await box.put('persona', updated.toJson());
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _loadBudget() async {
    try {
      final svc = PetTokenService.instance;
      await svc.loadBudget();
      _dailyBudget = svc.dailyBudget;
      // D8: 加载用量统计
      await _loadUsageStats();
    } catch (_) {}
  }

  Future<void> _loadUsageStats() async {
    try {
      final svc = PetTokenService.instance;
      final today = await svc.getTodayUsage();
      _todayUsed = today.totalTokens;
      final weekList = await svc.getWeekUsage();
      _weekUsed = weekList.fold(0, (sum, u) => sum + u.totalTokens);
      _monthUsed = await svc.getMonthUsage();
    } catch (_) {}
  }

  Future<void> _saveBudget(int? tokens) async {
    _dailyBudget = tokens;
    try {
      final svc = PetTokenService.instance;
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
      _visionModel = box.get('visionModel', defaultValue: '') as String;
      _visionApiKey = box.get('visionApiKey', defaultValue: '') as String;
      _visionBaseUrl = box.get('visionBaseUrl', defaultValue: '') as String;
      _visionKeyController.text = _visionApiKey;
      _chatContextRounds = box.get('chatContextRounds', defaultValue: 3) as int;
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
    PetLogger().info('PetSettings', 'toggle enabled=$enabled');
    try {
      if (enabled) {
        final granted = await _channel.invokeMethod<bool>('isOverlayPermissionGranted') ?? false;
        PetLogger().info('PetSettings', 'overlay permission: $granted');
        if (!granted) {
          await _channel.invokeMethod('requestOverlayPermission');
          PetLogger().info('PetSettings', 'requested overlay permission');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请授予悬浮窗权限后重新开启')),
            );
            // 权限未授予 → 回退开关，不保存 enabled=true
            setState(() => _config = _config.copyWith(enabled: false));
          }
          return;
        }
        // 权限已授予 → 保存配置
        await _saveConfig(_config.copyWith(enabled: true));
        // 先注册 Dart handler，再启动 native service，防止触控事件在 handler 就绪前到达
        petOverlayController.init();
        await _channel.invokeMethod('startPet');
        PetLogger().info('PetSettings', 'startPet sent to platform');
        petOverlayController.start();
      } else {
        await _saveConfig(_config.copyWith(enabled: false));
        petOverlayController.stop();
        await _channel.invokeMethod('stopPet');
        PetLogger().info('PetSettings', 'stopPet sent to platform');
      }
    } catch (e) {
      PetLogger().error('PetSettings', 'toggle failed', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('🐾 弗糯糯设置')),
        body: ListView(children: List.generate(6, (i) => const ShimmerCard(lines: 2))),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('🐾 弗糯糯设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
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
          _buildTokenDashboard(),
          const Divider(height: 32),
          _buildModelSection(),
          _buildContextRounds(),
          _buildExportButton(),
          const Divider(height: 32),
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
          onSelectionChanged: (s) { PetLogger().info('PetSettings', 'aiFrequency: ${s.first.name}'); _saveConfig(_config.copyWith(aiFrequency: s.first)); },
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
                PetLogger().info('PetSettings', 'triggerScenes: ${scene.name} ${active ? "off" : "on"}');
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
          onChanged: (v) { PetLogger().info('PetSettings', 'petScale: ${v.toStringAsFixed(1)}'); _saveConfig(_config.copyWith(petScale: v)); petOverlayController.syncScale(); },
        ),
      ],
    );
  }

  Widget _buildAutoStart() {
    return SwitchListTile(
      title: const Text('开机自启'),
      subtitle: const Text('手机重启后自动启动弗糯糯'),
      value: _config.autoStart,
      onChanged: (v) { PetLogger().info('PetSettings', 'autoStart: $v'); _saveConfig(_config.copyWith(autoStart: v)); },
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
          final now = DateTime.now();
          var until = DateTime(now.year, now.month, now.day, time.hour, time.minute);
          // 如果选的时间已经过了（如晚上选"到明早8点"），则推到明天
          if (until.isBefore(now)) until = until.add(const Duration(days: 1));
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
          initialValue: _persona.templateId != null
              && _personaTemplates.containsKey(_persona.templateId)
              ? _persona.templateId! : 'default',
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
            PetLogger().info('PetSettings', 'persona template: $v');
            _savePersona(_persona.copyWith(
              templateId: v,
              systemPrompt: prompts[v] ?? _persona.systemPrompt,
            ));
          },
        ),
        // ═══ 性格维度滑块 ═══
        const SizedBox(height: 16),
        Text('性格维度', style: C.body(context)),
        const SizedBox(height: 8),
        _TraitSlider(
          label: '活力',
          subtitle: _traits.energy.toStringAsFixed(1),
          value: _traits.energy,
          onChanged: (v) => setState(() => _traits = _traits.copyWith(energy: v)),
        ),
        _TraitSlider(
          label: '好奇心',
          subtitle: _traits.curiosity.toStringAsFixed(1),
          value: _traits.curiosity,
          onChanged: (v) => setState(() => _traits = _traits.copyWith(curiosity: v)),
        ),
        _TraitSlider(
          label: '粘人度',
          subtitle: _traits.clinginess.toStringAsFixed(1),
          value: _traits.clinginess,
          onChanged: (v) => setState(() => _traits = _traits.copyWith(clinginess: v)),
        ),
        _TraitSlider(
          label: '傲娇度',
          subtitle: _traits.tsundere.toStringAsFixed(1),
          value: _traits.tsundere,
          onChanged: (v) => setState(() => _traits = _traits.copyWith(tsundere: v)),
        ),
        _TraitSlider(
          label: '共情力',
          subtitle: _traits.empathy.toStringAsFixed(1),
          value: _traits.empathy,
          onChanged: (v) => setState(() => _traits = _traits.copyWith(empathy: v)),
        ),
        _TraitSlider(
          label: '幽默感',
          subtitle: _traits.humor.toStringAsFixed(1),
          value: _traits.humor,
          onChanged: (v) => setState(() => _traits = _traits.copyWith(humor: v)),
        ),

        // ═══ 说话风格 ═══
        const SizedBox(height: 16),
        Text('说话风格', style: C.body(context)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _selfRefCtrl,
                decoration: const InputDecoration(labelText: '自称', helperText: '如"糯糯"、"本喵"'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _endingCtrl,
                decoration: const InputDecoration(labelText: '句尾', helperText: '如"喵~"、"汪!"'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text('句子长度: ${_maxLen.round()}字'),
            ),
            Slider(
              value: _maxLen.toDouble(),
              min: 40,
              max: 200,
              onChanged: (v) => setState(() => _maxLen = v.round()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // System Prompt 编辑
        TextField(
          controller: _promptController,
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
        Text('按回车保存', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
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
        Text('超出额度后 Agent 暂停 LLM 调用，仅响应规则', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: List.generate(labels.length, (i) => ChoiceChip(
            label: Text(labels[i]),
            selected: selectedIdx == i,
            onSelected: (_) {
              PetLogger().info('PetSettings', 'budget: ${labels[i]}');
              _budgetController.clear();
              _saveBudget(values[i]);
              _loadUsageStats(); // D8: 刷新用量
            },
          )),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _budgetController,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(
            labelText: '自定义额度',
            hintText: '输入数字，如 75000',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onChanged: (v) {
            _budgetDebounce?.cancel();
            _budgetDebounce = Timer(const Duration(milliseconds: 500), () {
              final n = int.tryParse(v);
              if (n != null && n > 0 && mounted) {
                _saveBudget(n);
                _loadUsageStats(); // D8: 刷新用量
                setState(() {});
              }
            });
          },
        ),
      ],
    );
  }

  // ── D8: Token 用量仪表盘 ──

  Widget _buildTokenDashboard() {
    final budget = _dailyBudget ?? 50000;
    final todayPercent = budget > 0 ? (_todayUsed / budget).clamp(0.0, 1.0) : 0.0;
    final color = todayPercent > 0.8
        ? Colors.red
        : todayPercent > 0.5
            ? Colors.orange
            : Colors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text('📊 Token 用量', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        // 今日用量条
        Row(
          children: [
            const Text('今日', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: todayPercent,
                  minHeight: 10,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(_todayUsed / 1000).toStringAsFixed(1)}k / ${(budget / 1000).toStringAsFixed(0)}k',
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 本周 / 本月
        Row(
          children: [
            _buildUsageChip('本周', _weekUsed),
            const SizedBox(width: 12),
            _buildUsageChip('本月', _monthUsed),
          ],
        ),
        // 超预算警告
        if (todayPercent >= 1.0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
              const SizedBox(width: 4),
              Text(
                '今日预算已用尽，AI 仅响应主动聊天',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildUsageChip(String label, int tokens) {
    final k = (tokens / 1000).toStringAsFixed(1);
    return Chip(
      avatar: const Icon(Icons.token_outlined, size: 14),
      label: Text('$label: ${k}k', style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  // ── 模型选择 ──

  Widget _buildModelSection() {
    final mainModels = ModelConfig.builtIn
        .where((m) => m.id != 'custom-model' && m.id != 'mimo-v2-omni')
        .toList();
    final visionModels = ModelConfig.builtIn
        .where((m) => m.providerId == 'xiaomi' || m.id == 'gpt-4o')
        .toList();

    final mainModel = mainModels.firstWhere(
      (m) => m.modelId == _chatModel,
      orElse: () => mainModels.first,
    );
    final mainHasVision = visionModels.any((m) => m.modelId == _chatModel);

    String visionProvider;
    if (_visionModel.isEmpty) {
      visionProvider = mainModel.providerId;
    } else {
      final vm = visionModels.firstWhere(
        (m) => m.modelId == _visionModel,
        orElse: () => visionModels.first,
      );
      visionProvider = vm.providerId;
    }
    final showVisionKey = visionProvider != mainModel.providerId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🤖 模型配置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: mainModels.any((m) => m.modelId == _decisionModel) ? _decisionModel : 'deepseek-chat',
          decoration: const InputDecoration(
            labelText: '主模型（决策+聊天）',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: mainModels.map((m) => DropdownMenuItem(
            value: m.modelId,
            child: Text('${m.name} (${m.providerId})', style: const TextStyle(fontSize: 13)),
          )).toList(),
          onChanged: (v) {
            if (v != null) {
              PetLogger().info('PetSettings', 'mainModel: $v');
              _decisionModel = v;
              _chatModel = v;
              _saveModelSetting('decisionModel', v);
              _saveModelSetting('chatModel', v);
            }
          },
        ),
        const SizedBox(height: 24),
        const Text('👁️ 视觉分析', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text('主模型${mainHasVision ? '支持' : '不支持'}视觉能力。可独立选择视觉模型。',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('开启视觉分析'),
          subtitle: const Text('允许糯糯分析你的屏幕截图'),
          value: _visionEnabled,
          onChanged: (v) {
            PetLogger().info('PetSettings', 'visionEnabled: $v');
            _visionEnabled = v;
            _saveModelSetting('visionEnabled', v);
            if (mounted) setState(() {});
          },
        ),
        if (_visionEnabled) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _visionModel,
            decoration: const InputDecoration(
              labelText: '视觉模型',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('跟随主模型', style: TextStyle(fontSize: 13))),
              ...visionModels.map((m) => DropdownMenuItem(
                value: m.modelId,
                child: Text('${m.name} (${m.providerId})', style: const TextStyle(fontSize: 13)),
              )),
            ],
            onChanged: (v) {
              if (v != null) {
                _visionModel = v;
                _saveModelSetting('visionModel', v);
                if (mounted) setState(() {});
              }
            },
          ),
          if (_visionModel.isEmpty && !mainHasVision)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('⚠ 当前主模型无视觉能力，建议选择其他视觉模型',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error)),
            ),
        ],
        if (_visionEnabled && showVisionKey) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _visionKeyController,
            obscureText: true,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: '视觉 API Key',
              hintText: '视觉模型 provider 的 API Key',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (v) {
              _visionApiKey = v.trim();
              _saveModelSetting('visionApiKey', _visionApiKey);
            },
          ),
        ],
      ],
    );
  }

  // ── 聊天上下文轮数 ──

  Widget _buildContextRounds() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('聊天上下文轮数: $_chatContextRounds 轮',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text('每轮 = 用户消息 + AI 回复。0 轮 = 无上下文记忆',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
        Slider(
          value: _chatContextRounds.toDouble(),
          min: 0, max: 10, divisions: 10,
          label: '$_chatContextRounds 轮',
          onChanged: (v) {
            _chatContextRounds = v.round();
            PetLogger().info('PetSettings', 'chatContextRounds: $_chatContextRounds');
            _saveModelSetting('chatContextRounds', _chatContextRounds);
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }

  Widget _buildExportButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📋 调试日志', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('导出日志文件发送给开发者分析', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton.icon(
              onPressed: _exportLog,
              icon: const Icon(Icons.share, size: 16),
              label: const Text('导出日志'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _clearLog,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('清空日志'),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _exportLog() async {
    final logger = PetLogger();
    final content = await logger.getContent();

    if (!mounted) return;
    if (content == null || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无日志内容')),
      );
      return;
    }

    // 1. 保存 .txt 到临时目录
    File? txtFile;
    try { txtFile = await logger.exportTxt(); } catch (_) {}

    if (txtFile == null || !txtFile.existsSync()) {
      // 文件保存失败 → 兜底复制到剪贴板
      await Clipboard.setData(ClipboardData(text: content));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已复制到剪贴板 (${(content.length / 1024).toStringAsFixed(1)} KB)')),
        );
      }
      return;
    }

    // 2. 系统分享面板 → 直接分享 .txt 文件
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(txtFile.path, mimeType: 'text/plain')],
        subject: 'AI Chat 调试日志',
        text: '${content.substring(0, content.length.clamp(0, 300))}...',
      ));
    } catch (_) {
      // 分享失败 → 兜底剪贴板
      await Clipboard.setData(ClipboardData(text: content));
      if (mounted) {
        final sizeKb = (content.length / 1024).toStringAsFixed(1);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享面板未打开，已复制到剪贴板 ($sizeKb KB)')),
        );
      }
    }
  }

  Future<void> _clearLog() async {
    await PetLogger().clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日志已清空')),
      );
    }
  }

  String _sceneLabel(TriggerScene s) => switch (s) {
    TriggerScene.browser => '浏览器',
    TriggerScene.document => '文档',
    TriggerScene.settings => '设置',
    TriggerScene.all => '全部',
  };
}

// Flutter 3.24 / Dart 3.5
class _TraitSlider extends StatelessWidget {
  final String label;
  final String subtitle;
  final double value;
  final ValueChanged<double> onChanged;

  const _TraitSlider({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(subtitle, style: const TextStyle(fontSize: 11), textAlign: TextAlign.right),
        ),
      ],
    );
  }
}
