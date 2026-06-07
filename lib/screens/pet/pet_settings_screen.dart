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
import 'pet_persona_screen.dart';

class PetSettingsScreen extends StatefulWidget {
  const PetSettingsScreen({super.key});

  @override
  State<PetSettingsScreen> createState() => _PetSettingsScreenState();
}

class _PetSettingsScreenState extends State<PetSettingsScreen> {
  static const _channel = MethodChannel('com.example.deepseek_chat/pet_service');

  PetConfig _config = PetConfig();
  bool _loaded = false;

  /// 缓存 Hive Box，避免每次读写都 openBox
  Box? _configBox;

  PetPersona _persona = PetPersona();
  late final TextEditingController _budgetController;
  Timer? _budgetDebounce;
  int? _dailyBudget = 50000;
  int _todayUsed = 0;
  int _weekUsed = 0;
  int _monthUsed = 0;
  int _chatContextRounds = 3;
  String _decisionModel = 'deepseek-v4-pro';
  String _chatModel = 'deepseek-v4-pro';
  bool _followMainModel = true; // 默认跟随主聊天模型
  String _visionModel = '';
  String _visionApiKey = '';
  late final TextEditingController _visionKeyController;
  bool _visionEnabled = false;

  /// 角色模式：(systemPrompt, emoji, aiFrequency, label)
  static final _roleModes = <String, (String, String, AiFrequency, String)>{
    'default': (
      '你是${petOverlayController.personaName}，一只可爱的虚拟宠物精灵。性格：软萌、粘人、偶尔丧丧的摆烂。自称"${petOverlayController.petSelfRef}"，句尾加"喵~"。保持短小可爱，不超过2句话。',
      '🐱', AiFrequency.occasional, '陪伴'
    ),
    'assistant': (
      '你是${petOverlayController.personaName}，一个高效的AI桌面助理。性格：直接、高效、少卖萌。自称"${petOverlayController.petSelfRef}"，不用句尾语。优先给出有用的建议和提醒。保持简洁，1句话说清楚。',
      '🧠', AiFrequency.occasional, '助理'
    ),
    'entertainment': (
      '你是${petOverlayController.personaName}，一只幽默爱吐槽的电子宠物。性格：毒舌、段子手、随意发挥。自称"${petOverlayController.petSelfRef}"，句尾加"喵~"或"哈哈哈哈"。吐槽生活、讲冷笑话、制造快乐。不超过2句话。',
      '🎮', AiFrequency.chatty, '娱乐'
    ),
    'focus': (
      '你是${petOverlayController.personaName}，一只安静守护的电子宠物。性格：沉默、克制、只在必要时说话。自称"${petOverlayController.petSelfRef}"。除非用户叫或极度危险，否则保持沉默。最多1句话，不超过15个字。',
      '📵', AiFrequency.silent, '专注'
    ),
  };

  @override
  void initState() {
    super.initState();
    _budgetController = TextEditingController();
    _visionKeyController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConfig());
  }


  Future<void> _loadConfig() async {
    PetLogger().info('PetSettings', 'loadConfig()');
    try {
      // 预打开 Box 缓存，后续读写复用
      _configBox = await Hive.openBox('pet_config');
      await Future.wait([
        _loadPersona(),
        _loadBudget(),
        _loadModelSettings(),
        () async {
          try { _config = await PetService.loadConfig(); } catch (_) {}
        }(),
      ]);
    } catch (e) {
      PetLogger().error('PetSettings', 'loadConfig failed', e);
    }
    if (mounted) {
      setState(() => _loaded = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsageStats());
    }
  }

  Future<void> _loadPersona() async {
    _persona = petOverlayController.personaStore?.persona ?? PetPersona();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _budgetDebounce?.cancel();
    _budgetController.dispose();
    _visionKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadBudget() async {
    try {
      final svc = PetTokenService.instance;
      await svc.loadBudget();
      _dailyBudget = svc.dailyBudget;
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
      if (mounted) setState(() {});
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
      final box = _configBox;
      if (box == null) return;
      _decisionModel = box.get('decisionModel', defaultValue: 'deepseek-v4-pro') as String;
      _chatModel = box.get('chatModel', defaultValue: 'deepseek-v4-pro') as String;
      _visionEnabled = box.get('visionEnabled', defaultValue: false) as bool;
      _visionModel = box.get('visionModel', defaultValue: '') as String;
      _visionApiKey = box.get('visionApiKey', defaultValue: '') as String;
      _visionKeyController.text = _visionApiKey;
      _chatContextRounds = box.get('chatContextRounds', defaultValue: 3) as int;
      _followMainModel = box.get('followMainModel', defaultValue: true) as bool;
    } catch (_) {}
  }

  Future<void> _saveModelSetting(String key, dynamic value) async {
    try {
      await _configBox?.put(key, value);
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
        if (!granted) {
          await _channel.invokeMethod('requestOverlayPermission');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请授予悬浮窗权限后重新开启')),
            );
            setState(() => _config = _config.copyWith(enabled: false));
          }
          return;
        }
        await _saveConfig(_config.copyWith(enabled: true));
        petOverlayController.init();
        await _channel.invokeMethod('startPet');
        petOverlayController.start();
      } else {
        await _saveConfig(_config.copyWith(enabled: false));
        petOverlayController.stop();
        await _channel.invokeMethod('stopPet');
      }
    } catch (e) {
      PetLogger().error('PetSettings', 'toggle failed', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('🐾 设置')),
        body: ListView(children: List.generate(4, (i) => const ShimmerCard(lines: 2))),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('🐾 设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        physics: const BouncingScrollPhysics(),
        children: [
          _buildBasicSection(),
          _buildPersonaSection(),
          _buildBudgetSection(),
          _buildModelSection(),
          _buildAppearanceSection(),
          _buildDebugSection(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 1. 基本设置 (默认展开)
  // ═══════════════════════════════════════════

  Widget _buildBasicSection() {
    return ExpansionTile(
      leading: const Icon(Icons.pets),
      title: const Text('基本设置'),
      initiallyExpanded: true,
      children: [
        SwitchListTile(
          title: const Text('开启宠物'),
          subtitle: const Text('在任意应用上层显示电子宠物'),
          value: _config.enabled,
          onChanged: _toggleEnabled,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AI 主动建议频率', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              SegmentedButton<AiFrequency>(
                segments: const [
                  ButtonSegment(value: AiFrequency.silent, label: Text('安静')),
                  ButtonSegment(value: AiFrequency.occasional, label: Text('偶尔')),
                  ButtonSegment(value: AiFrequency.chatty, label: Text('话多')),
                ],
                selected: {_config.aiFrequency},
                onSelectionChanged: (s) {
                  _saveConfig(_config.copyWith(aiFrequency: s.first));
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('触发场景', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
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
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // 2. 性格设置
  // ═══════════════════════════════════════════

  Widget _buildPersonaSection() {
    return ExpansionTile(
      initiallyExpanded: true,
      leading: const Icon(Icons.psychology, color: Color(0xFFA78BFA)),
      title: const Text('性格设置'),
      children: [
        // 人格编辑主页
        ListTile(
          leading: const Icon(Icons.edit, size: 20),
          title: const Text('编辑人格', style: TextStyle(fontSize: 14)),
          subtitle: const Text('名字·自称·性格滑块·System Prompt', style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, size: 18),
          dense: true,
          onTap: () async {
            final store = petOverlayController.personaStore;
            if (store == null) {
              // KB 尚未初始化，先触发初始化
              await petOverlayController.ensureKB();
              await Future.delayed(const Duration(milliseconds: 100));
            }
            final ready = petOverlayController.personaStore;
            if (!mounted) return;
            if (ready == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请先开启宠物再调整人格'), duration: Duration(seconds: 2)),
              );
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PetPersonaScreen(personaStore: ready)),
            );
          },
        ),
        const Divider(indent: 72),
        // ── 角色模式 ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('角色模式', style: C.label(context).copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _roleModes.entries.map((e) {
                    final selected = _persona.templateId == e.key;
                    final emoji = e.value.$2;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          final mode = e.value;
                          final p = _persona.copyWith(templateId: e.key, systemPrompt: mode.$1);
                          _persona = p;
                          (() {
  final store = petOverlayController.personaStore;
  if (store != null) { store.saveOverwrite(p); }
  else { PetLogger().error('PetSettings', 'saveOverwrite FAILED: personaStore is null'); }
})();
                          _config = _config.copyWith(aiFrequency: mode.$3);
                          _saveConfig(_config);
                          if (mounted) setState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected ? C.scheme.primaryContainer : C.scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: selected ? Border.all(color: C.scheme.primary) : null,
                          ),
                          child: Column(
                            children: [
                              Text(emoji, style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 4),
                              Text(e.value.$4, style: TextStyle(fontSize: 12, color: selected ? C.scheme.onPrimaryContainer : C.scheme.onSurface.withAlpha(180))),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        // 精细调整请进入「编辑人格」页面
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('名字、自称、性格滑块、System Prompt 请在「编辑人格」中调整',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(150))),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // 3. Token 管理
  // ═══════════════════════════════════════════

  Widget _buildBudgetSection() {
    final budget = _dailyBudget ?? 50000;
    final todayPercent = budget > 0 ? (_todayUsed / budget).clamp(0.0, 1.0) : 0.0;
    final color = todayPercent > 0.8 ? Colors.red : todayPercent > 0.5 ? Colors.orange : Colors.green;
    final labels = ['10k', '30k', '50k', '100k', '不限'];
    final values = <int?>[10000, 30000, 50000, 100000, null];
    final selectedIdx = values.indexOf(_dailyBudget);

    return ExpansionTile(
      leading: const Icon(Icons.token, color: Colors.amber),
      title: const Text('Token 管理'),
      children: [
        // Token 说明
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withAlpha(60)),
            ),
            child: Text(
              'Token 是 AI 语言模型的计算单位，约 1 个中文字 ≈ 2 Token。\n'
              '每日额度控制${petOverlayController.petSelfRef}主动说话、写日记、整理记忆的总消耗。\n'
              '用完后${petOverlayController.petSelfRef}会进入 💤 静默模式，仅响应用户主动聊天。',
              style: TextStyle(fontSize: 12, height: 1.6, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('每日额度', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text('超出额度后 Agent 暂停 LLM 调用',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(140))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: List.generate(labels.length, (i) => ChoiceChip(
                  label: Text(labels[i], style: const TextStyle(fontSize: 12)),
                  selected: selectedIdx == i,
                  onSelected: (_) {
                    _budgetController.clear();
                    _saveBudget(values[i]);
                    _loadUsageStats();
                  },
                )),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _budgetController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '自定义额度',
                  hintText: '如 75000',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (v) {
                  _budgetDebounce?.cancel();
                  _budgetDebounce = Timer(const Duration(milliseconds: 500), () {
                    final n = int.tryParse(v);
                    if (n != null && n > 0 && mounted) {
                      _saveBudget(n);
                      _loadUsageStats();
                      setState(() {});
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              // 用量条
              Row(
                children: [
                  const Text('今日', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: todayPercent,
                        minHeight: 8,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(_todayUsed / 1000).toStringAsFixed(1)}k/${(budget / 1000).toStringAsFixed(0)}k',
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _usageChip('本周', _weekUsed),
                  const SizedBox(width: 10),
                  _usageChip('本月', _monthUsed),
                ],
              ),
              if (todayPercent >= 1.0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('今日预算已用尽', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _usageChip(String label, int tokens) {
    return Chip(
      avatar: const Icon(Icons.token_outlined, size: 13),
      label: Text('$label: ${(tokens / 1000).toStringAsFixed(1)}k', style: const TextStyle(fontSize: 10)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  // ═══════════════════════════════════════════
  // 4. 模型配置
  // ═══════════════════════════════════════════

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
      final vm = visionModels.firstWhere((m) => m.modelId == _visionModel, orElse: () => visionModels.first);
      visionProvider = vm.providerId;
    }
    final showVisionKey = visionProvider != mainModel.providerId;

    return ExpansionTile(
      leading: const Icon(Icons.smart_toy, color: Colors.blue),
      title: const Text('模型配置'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _followMainModel ? '__follow__' : (_decisionModel),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '主模型',
                  hintText: '决策 + 聊天',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 13),
                items: [
                  const DropdownMenuItem(value: '__follow__', child: Text('跟随主聊天模型', style: TextStyle(fontSize: 13, color: Color(0xFF8EC8B0)))),
                  ...mainModels.map((m) => DropdownMenuItem(
                    value: m.modelId,
                    child: Text(m.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                  )),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  if (v == '__follow__') {
                    _followMainModel = true;
                    _saveModelSetting('followMainModel', true);
                    // 跟随主模型时用主聊天的模型
                    var mainModelId = 'deepseek-v4-pro';
                    try {
                      final settingsBox = await Hive.openBox('settings');
                      mainModelId = settingsBox.get('selectedModelId', defaultValue: 'deepseek-v4-pro') as String;
                    } catch (_) {}
                    _decisionModel = mainModelId;
                    _chatModel = mainModelId;
                    _saveModelSetting('decisionModel', mainModelId);
                    _saveModelSetting('chatModel', mainModelId);
                    if (mounted) setState(() {});
                    return;
                  }
                  _followMainModel = false;
                  _saveModelSetting('followMainModel', false);
                  // 检查该模型所属 provider 是否有 API Key
                  final config = mainModels.firstWhere((m) => m.modelId == v);
                  final provider = ModelConfig.providers.firstWhere((p) => p.id == config.providerId);
                  if (provider.id != 'deepseek') {
                    // 非 DeepSeek 需要检查 API Key
                    String? savedKey;
                    try {
                      final settingsBox = await Hive.openBox('settings');
                      savedKey = settingsBox.get('${provider.id}_key') as String?;
                    } catch (_) {}
                    if ((savedKey == null || savedKey.isEmpty) && mounted) {
                      final ctrl = TextEditingController();
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('${provider.name} 需要 API Key'),
                          content: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text('使用 ${provider.name} 的模型需要填写 API Key。\n请到 ${provider.name} 官网获取。', style: const TextStyle(fontSize: 14)),
                            const SizedBox(height: 12),
                            TextField(controller: ctrl, obscureText: true, decoration: InputDecoration(
                              labelText: '${provider.name} API Key',
                              border: const OutlineInputBorder(),
                              hintText: '粘贴你的 API Key',
                            )),
                          ]),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('稍后')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        final key = ctrl.text.trim();
                        if (key.isNotEmpty) {
                          try {
                            final settingsBox = await Hive.openBox('settings');
                            await settingsBox.put('${provider.id}_key', key);
                          } catch (_) {}
                        }
                      }
                    }
                  }
                  _decisionModel = v;
                  _chatModel = v;
                  _saveModelSetting('decisionModel', v);
                  _saveModelSetting('chatModel', v);
                },
              ),
              const SizedBox(height: 16),
              const Text('视觉分析', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text('主模型${mainHasVision ? '支持' : '不支持'}视觉能力',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(140))),
              SwitchListTile(
                title: const Text('开启视觉分析', style: TextStyle(fontSize: 14)),
                value: _visionEnabled,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) {
                  _visionEnabled = v;
                  _saveModelSetting('visionEnabled', v);
                  if (mounted) setState(() {});
                },
              ),
              if (_visionEnabled) ...[
                DropdownButtonFormField<String>(
                  initialValue: _visionModel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '视觉模型',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('跟随主模型', style: TextStyle(fontSize: 13))),
                    ...visionModels.map((m) => DropdownMenuItem(
                      value: m.modelId,
                      child: Text(m.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (v) {
                    if (v != null) { _visionModel = v; _saveModelSetting('visionModel', v); if (mounted) setState(() {}); }
                  },
                ),
                if (_visionModel.isEmpty && !mainHasVision)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('⚠ 当前主模型无视觉能力',
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
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (v) { _visionApiKey = v.trim(); _saveModelSetting('visionApiKey', _visionApiKey); },
                ),
              ],
              const SizedBox(height: 12),
              Text('聊天上下文轮数: $_chatContextRounds 轮', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Slider(
                value: _chatContextRounds.toDouble(),
                min: 0, max: 10, divisions: 10,
                label: '$_chatContextRounds 轮',
                onChanged: (v) {
                  _chatContextRounds = v.round();
                  _saveModelSetting('chatContextRounds', _chatContextRounds);
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // 5. 外观 & 行为
  // ═══════════════════════════════════════════

  Widget _buildAppearanceSection() {
    return ExpansionTile(
      leading: const Icon(Icons.palette, color: Colors.teal),
      title: const Text('外观 & 行为'),
      children: [
        // 皮肤系统 Phase 3 实现
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('宠物大小: ${_config.petScale.toStringAsFixed(1)}x',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Slider(
                value: _config.petScale,
                min: 0.5, max: 1.5, divisions: 10,
                onChanged: (v) { _saveConfig(_config.copyWith(petScale: v)); petOverlayController.syncScale(); },
              ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('开机自启', style: TextStyle(fontSize: 14)),
          subtitle: const Text('重启后自动启动'),
          value: _config.autoStart,
          dense: true,
          onChanged: (v) => _saveConfig(_config.copyWith(autoStart: v)),
        ),
        ListTile(
          title: const Text('免打扰', style: TextStyle(fontSize: 14)),
          subtitle: Text(_config.quietUntil == null ? '未设置' : '至 ${_config.quietUntil!.hour}:${_config.quietUntil!.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 13)),
          trailing: _config.quietUntil != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => _saveConfig(_config.copyWith(quietUntil: PetConfig.clearSentinel)),
                )
              : null,
          dense: true,
          onTap: () async {
            final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
            if (time != null) {
              final now = DateTime.now();
              var until = DateTime(now.year, now.month, now.day, time.hour, time.minute);
              if (until.isBefore(now)) until = until.add(const Duration(days: 1));
              await _saveConfig(_config.copyWith(quietUntil: until));
            }
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // 6. 调试 & 导出
  // ═══════════════════════════════════════════

  Widget _buildDebugSection() {
    return ExpansionTile(
      leading: const Icon(Icons.bug_report, color: Colors.grey),
      title: const Text('调试 & 导出'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('导出日志文件发送给开发者分析',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(140))),
              const SizedBox(height: 8),
              Row(children: [
                ElevatedButton.icon(
                  onPressed: _exportLog,
                  icon: const Icon(Icons.share, size: 16),
                  label: const Text('导出日志', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _clearLog,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('清空日志', style: TextStyle(fontSize: 13)),
                ),
              ]),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════

  Future<void> _exportLog() async {
    final logger = PetLogger();
    final content = await logger.getContent();
    if (!mounted) return;
    if (content == null || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无日志内容')));
      return;
    }

    File? txtFile;
    try { txtFile = await logger.exportTxt(); } catch (_) {}

    if (txtFile == null || !txtFile.existsSync()) {
      await Clipboard.setData(ClipboardData(text: content));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已复制到剪贴板 (${(content.length / 1024).toStringAsFixed(1)} KB)')),
        );
      }
      return;
    }

    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(txtFile.path, mimeType: 'text/plain')],
        subject: 'AI Chat 调试日志',
        text: '${content.substring(0, content.length.clamp(0, 300))}...',
      ));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: content));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已复制到剪贴板 (${(content.length / 1024).toStringAsFixed(1)} KB)')),
        );
      }
    }
  }

  Future<void> _clearLog() async {
    await PetLogger().clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日志已清空')));
    }
  }

  String _sceneLabel(TriggerScene s) => switch (s) {
    TriggerScene.browser => '浏览器',
    TriggerScene.document => '文档',
    TriggerScene.settings => '设置',
    TriggerScene.all => '全部',
  };
}
