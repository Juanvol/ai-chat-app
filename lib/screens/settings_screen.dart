import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/model_config.dart';
import '../main.dart' show themeModeNotifier;
import '../services/app/conversation_service.dart';
import '../utils/page_routes.dart';
import 'token_stats_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SSState();
}

class _SSState extends State<SettingsScreen> {
  final _keys = <String, TextEditingController>{};
  final _promptCtrl = TextEditingController();
  late final TextEditingController _rateCtrl;
  String _model = 'ds-v4-pro';
  bool _loaded = false;
  int _maxTokens = 4096;
  double _temp = 0.7;
  int _rateLimit = 20;
  bool _showMoreKeys = false;
  final Set<String> _expandedProviders = {'deepseek'};
  bool _thinkingEnabled = true;
  String _reasoningEffort = 'high';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final svc = context.read<ConversationService>();
    for (final p in ModelConfig.providers) {
      _keys[p.id] = TextEditingController(text: svc.storage.get('${p.id}_key', '') ?? '');
    }
    _promptCtrl.text = svc.storage.get('system_prompt', '') ?? '';
    _model = svc.storage.selModel;
    _maxTokens = svc.globalMaxTokens;
    _temp = svc.globalTemperature;
    _rateLimit = svc.rateLimitPerMinute;
    _thinkingEnabled = svc.thinkingEnabled;
    _reasoningEffort = svc.reasoningEffort;
    _rateCtrl = TextEditingController(text: _rateLimit.toString());
    _loaded = true;
  }

  void _setTheme(ThemeMode mode) {
    themeModeNotifier.value = mode;
    final svc = context.read<ConversationService>();
    svc.storage.save('theme_mode',
      switch (mode) { ThemeMode.dark => 'dark', ThemeMode.light => 'light', _ => 'system' });
  }

  void _save() {
    final svc = context.read<ConversationService>();
    for (final p in ModelConfig.providers) {
      svc.storage.save('${p.id}_key', _keys[p.id]!.text.trim());
    }
    svc.storage.setApiKey(_keys['deepseek']!.text.trim());
    svc.storage.setSelModel(_model);
    svc.storage.save('system_prompt', _promptCtrl.text.trim());
    svc.client.setApiKey(_keys['deepseek']!.text.trim());
    svc.client.setSystemPrompt(_promptCtrl.text.trim());
    svc.saveThinking(enabled: _thinkingEnabled, effort: _reasoningEffort);
    svc.saveSettings(maxTokens: _maxTokens, temperature: _temp, rateLimit: _rateLimit);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
    );
  }

  String? get _curPid => ModelConfig.builtIn.where((m) => m.id == _model).firstOrNull?.providerId;

  List<ModelConfig> _modelsForProvider(String pid) =>
      ModelConfig.builtIn.where((m) => m.providerId == pid).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Hero(tag: 'hero_title_设置', child: Text('设置')), actions: [
        TextButton(onPressed: _save, child: const Text('保存')),
      ]),
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: C.s16, vertical: C.s12), physics: const BouncingScrollPhysics(), children: [
        // === 密钥 ===
        _section('API 密钥'),
        const SizedBox(height: C.s8),
        _keyRow('deepseek'),
        _keyRow('xiaomi'),
        _keyRow('siliconflow'),
        GestureDetector(
          onTap: () => setState(() => _showMoreKeys = !_showMoreKeys),
          child: Padding(
            padding: const EdgeInsets.only(top: C.s4),
            child: Text(_showMoreKeys ? '收起 ▲' : '更多密钥... ▼', style: C.caption),
          ),
        ),
        if (_showMoreKeys) ...[
          const SizedBox(height: C.s8),
          _keyRow('openai'),
          _keyRow('zhipu'),
          _keyRow('moonshot'),
          _keyRow('custom'),
        ],

        const SizedBox(height: C.s20),

        // === System Prompt ===
        _section('系统提示词'),
        const SizedBox(height: C.s8),
        TextField(controller: _promptCtrl, maxLines: 2, style: C.body,
          decoration: const InputDecoration(hintText: '例如：请用中文回复。书名、技术术语、人名等专有名词保留原文。', isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        ),

        const SizedBox(height: C.s20),

        // === 模型 ===
        _section('模型'),
        const SizedBox(height: C.s4),
        _buildModelList(),

        const SizedBox(height: C.s16),

        // === 使用设置 ===
        _section('使用设置'),
        const SizedBox(height: C.s12),

        // Thinking 模式
        Text('思考模式 (Thinking)', style: C.body),
        const SizedBox(height: C.s4),
        Text('开启后 AI 会先推理再回答，质量更高但稍慢。V4 Pro/Flash 默认开启。', style: C.caption),
        const SizedBox(height: C.s8),
        SwitchListTile(
          value: _thinkingEnabled,
          onChanged: (v) => setState(() => _thinkingEnabled = v),
          title: Text(_thinkingEnabled ? '已开启' : '已关闭', style: C.body),
          dense: true, contentPadding: EdgeInsets.zero,
          activeThumbColor: const Color(0xFFA78BFA),
        ),

        if (_thinkingEnabled) ...[
          const SizedBox(height: C.s4),
          Text('推理强度', style: C.label),
          const SizedBox(height: C.s4),
          Text('控制 AI 在回答前进行内部推理的深度。推理越深，回答质量越高，但消耗的 Token 也越多。', style: C.caption),
          const SizedBox(height: C.s8),
          Wrap(spacing: C.s8, children: ['low', 'medium', 'high', 'max'].map((e) => ChoiceChip(
            label: Text(
              switch (e) {
                'low' => '低',
                'medium' => '中',
                'high' => '高 (推荐)',
                'max' => '最大',
                _ => e,
              },
              style: const TextStyle(fontSize: 12)),
            selected: _reasoningEffort == e,
            onSelected: (_) => setState(() => _reasoningEffort = e),
            selectedColor: C.scheme.primary.withValues(alpha: 0.2),
          )).toList()),
          const SizedBox(height: C.s8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(C.r8),
              border: Border.all(color: const Color(0xFFDDD6FE)),
            ),
            child: Text(
              switch (_reasoningEffort) {
                'low' => '低推理：几乎不额外消耗 Token，响应最快。适合简单问答、闲聊、翻译。',
                'medium' => '中推理：适度思考，少量 Token 消耗。适合一般对话、知识问答。',
                'high' => '高推理（推荐）：深度思考后再回答，Token 消耗适中。适合日常使用，质量与成本的最佳平衡。',
                'max' => '最大推理：最深层的推理过程，消耗最多 Token。适合数学证明、复杂编程、逻辑推理等高难度任务。⚠ 注意：token 消耗会显著增加。',
                _ => '',
              },
              style: C.caption,
            ),
          ),
        ],

        const SizedBox(height: C.s16),

        // 温度 (V4 不支持)
        Text('温度', style: C.body),
        const SizedBox(height: C.s4),
        Text('⚠ V4 Pro/Flash 不支持温度调节，此设置无效。仅对旧版模型 (deepseek-chat) 有效。', style: C.caption),
        const SizedBox(height: C.s4),
        Row(children: [
          const Text('0', style: TextStyle(color: Color(0xFF5B5B65), fontSize: 11)),
          Expanded(child: Slider(value: _temp, min: 0.0, max: 1.5, divisions: 15, onChanged: (v) => setState(() => _temp = v))),
          const Text('1.5', style: TextStyle(color: Color(0xFF5B5B65), fontSize: 11)),
        ]),
        Center(child: Text('${_temp.toStringAsFixed(1)} — ${_tempDesc(_temp)}', style: C.caption)),

        const SizedBox(height: C.s16),

        // Max Tokens
        Text('最大输出长度', style: C.body),
        const SizedBox(height: C.s4),
        Text('控制 AI 每次回复的最大长度（含推理和回答）。点击预设值快速选择，或拖动滑块微调。值越大回答越完整，但 Token 消耗也越多。', style: C.caption),
        const SizedBox(height: C.s8),
        Wrap(spacing: C.s8, children: [512, 1024, 2048, 4096, 8192, 16384, 32768].map((v) => ChoiceChip(
          label: Text(v >= 1024 ? '${(v / 1024).toStringAsFixed(v == 512 ? 1 : 0)}K' : '$v', style: const TextStyle(fontSize: 12)),
          selected: _maxTokens == v,
          onSelected: (_) => setState(() { _maxTokens = v; }),
          selectedColor: C.scheme.primary.withValues(alpha: 0.2),
        )).toList()),
        const SizedBox(height: C.s8),
        Row(children: [
          const Text('512', style: TextStyle(color: Color(0xFF5B5B65), fontSize: 11)),
          Expanded(child: Slider(
            value: _maxTokens.toDouble(),
            min: 512, max: 32768, divisions: 63,
            onChanged: (v) => setState(() { _maxTokens = v.round(); }),
          )),
          const Text('32K', style: TextStyle(color: Color(0xFF5B5B65), fontSize: 11)),
        ]),
        Center(child: Text('$_maxTokens tokens ≈ ${(_maxTokens / 2).round()} 中文字', style: C.caption)),
        const SizedBox(height: C.s8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(C.r8),
            border: Border.all(color: const Color(0xFFDDD6FE)),
          ),
          child: Text(
            '💡 使用建议：\n'
            '• 0.5K–2K：简短问答、翻译、闲聊\n'
            '• 4K–8K：一般对话、代码生成、文章写作（推荐）\n'
            '• 16K–32K：长文生成、大批量代码、深度分析\n'
            '⚠ 注意：已开启推理时，推理过程也计入 Token 上限。强度越高建议预留越大。',
            style: C.caption,
          ),
        ),

        const SizedBox(height: C.s16),

        // 速率
        Text('每分钟请求上限', style: C.body),
        const SizedBox(height: C.s4),
        Text('防止误操作或程序死循环导致 API 费用飙升。达到上限后暂停发送。免费用户建议 5-10，付费用户 20-30。', style: C.caption),
        const SizedBox(height: C.s8),
        Row(children: [
          const Spacer(),
          SizedBox(width: 80, child: TextField(
            controller: _rateCtrl,
            style: C.body, textAlign: TextAlign.center, keyboardType: TextInputType.number,
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            onChanged: (v) { final n = int.tryParse(v); if (n != null && n > 0) _rateLimit = n; },
          )),
        ]),

        const SizedBox(height: C.s16),

        // 外观
        _section('外观'),
        const SizedBox(height: C.s8),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (_, mode, __) => RadioGroup<ThemeMode>(
            groupValue: mode,
            onChanged: (v) => _setTheme(v!),
            child: const Column(children: [
            RadioListTile<ThemeMode>(
              value: ThemeMode.light, title: Text('浅色', style: TextStyle(fontSize: 15)),
              dense: true, contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
            ),
            RadioListTile<ThemeMode>(
              value: ThemeMode.dark, title: Text('深色', style: TextStyle(fontSize: 15)),
              dense: true, contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
            ),
            RadioListTile<ThemeMode>(
              value: ThemeMode.system, title: Text('跟随系统', style: TextStyle(fontSize: 15)),
              dense: true, contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
            ),
          ]),
          ),
        ),

        const SizedBox(height: C.s32),

        // Token 用量统计入口
        ListTile(
          leading: const Icon(Icons.bar_chart_rounded, color: Color(0xFFA78BFA)),
          title: const Text('Token 用量统计', style: TextStyle(fontSize: 15)),
          subtitle: const Text('查看 API 调用次数、Token 消耗与费用', style: TextStyle(fontSize: 13)),
          trailing: const Icon(Icons.chevron_right, size: 20),
          contentPadding: EdgeInsets.zero,
          onTap: () => pushElastic(context, const TokenStatsScreen()),
        ),

        const SizedBox(height: C.s32),
      ]),
    );
  }

  Widget _section(String t) => Text(t, style: C.label);

  Widget _buildModelList() {
    final providerOrder = ['deepseek', 'xiaomi', 'openai', 'siliconflow', 'zhipu', 'moonshot', 'custom'];
    final widgets = <Widget>[];
    for (final pid in providerOrder) {
      final models = _modelsForProvider(pid);
      if (models.isEmpty) continue;
      final provider = ModelConfig.providers.where((p) => p.id == pid).firstOrNull;
      final isExpanded = _expandedProviders.contains(pid);
      final selectedModel = models.where((m) => m.id == _model).firstOrNull;
      final isSelectedProvider = selectedModel != null;

      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: C.s4),
          decoration: BoxDecoration(
            border: Border.all(color: isSelectedProvider ? const Color(0xFFA78BFA).withValues(alpha: 0.5) : const Color(0xFFE5E5E5)),
            borderRadius: BorderRadius.circular(C.r8),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() {
                  if (isExpanded) {
                    _expandedProviders.remove(pid);
                  } else {
                    _expandedProviders.add(pid);
                  }
                }),
                borderRadius: BorderRadius.vertical(top: const Radius.circular(C.r8), bottom: isExpanded ? Radius.zero : const Radius.circular(C.r8)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    if (isSelectedProvider)
                      Container(width: 6, height: 6, margin: const EdgeInsets.only(right: C.s8),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFA78BFA))),
                    Text(provider?.name ?? pid, style: isSelectedProvider ? C.body.copyWith(fontWeight: FontWeight.w600) : C.body),
                    if (isSelectedProvider)
                      Padding(
                        padding: const EdgeInsets.only(left: C.s8),
                        child: Text(selectedModel.name, style: C.caption.copyWith(color: const Color(0xFFA78BFA))),
                      ),
                    const Spacer(),
                    Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 20, color: const Color(0xFF9D9DA8)),
                  ]),
                ),
              ),
              if (isExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: RadioGroup<String>(
                    groupValue: _model,
                    onChanged: (v) => setState(() => _model = v!),
                    child: Column(
                    children: models.map((m) => RadioListTile<String>(
                      value: m.id,
                      title: Row(children: [
                        Expanded(child: Text(m.name, style: C.body.copyWith(fontSize: 15))),
                        Text(
                          '¥${m.inputPricePerM.toStringAsFixed(m.inputPricePerM == m.inputPricePerM.roundToDouble() ? 0 : 2)} / ¥${m.outputPricePerM.toStringAsFixed(m.outputPricePerM == m.outputPricePerM.roundToDouble() ? 0 : 2)}',
                          style: C.caption,
                        ),
                      ]),
                      subtitle: Text(m.description, style: C.caption.copyWith(fontSize: 12)),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.only(left: 4),
                    )).toList(),
                  ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Column(children: widgets);
  }

  Widget _keyRow(String pid) {
    final p = ModelConfig.providers.where((p) => p.id == pid).firstOrNull;
    final isCur = pid == _curPid;
    return Row(children: [
      if (isCur)
        Container(width: 6, height: 6, margin: const EdgeInsets.only(right: C.s4),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFA78BFA))),
      SizedBox(width: isCur ? 54 : 64, child: Text(p?.name ?? pid, style: C.caption)),
      const SizedBox(width: C.s8),
      Expanded(child: TextField(
        controller: _keys[pid], obscureText: true, style: C.body,
        decoration: InputDecoration(hintText: '点击粘贴 API Key...', isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          suffixIcon: IconButton(
            icon: const Icon(Icons.paste_outlined, size: 18),
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final text = data?.text ?? '';
              if (text.isNotEmpty) {
                _keys[pid]!.text = text;
                setState(() {});
              }
            },
          ),
        ),
      )),
    ]);
  }

  String _tempDesc(double t) {
    if (t <= 0.3) return '精确';
    if (t <= 0.6) return '保守';
    if (t <= 0.9) return '平衡';
    if (t <= 1.2) return '创意';
    return '发散';
  }

  @override
  void dispose() {
    for (final c in _keys.values) { c.dispose(); }
    _promptCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }
}
