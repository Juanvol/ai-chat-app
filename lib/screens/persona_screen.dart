// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/persona.dart';
import '../services/app/persona_service.dart';

class PersonaScreen extends StatelessWidget {
  const PersonaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Hero(tag: 'hero_title_人格管理', child: Text('人格画廊')), actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.add, size: 20),
          onSelected: (v) {
            switch (v) {
              case 'mbti': _showMbtiSheet(context); break;
              case 'emotion': _showEmotionSheet(context); break;
              case 'custom': _edit(context, null); break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'mbti', child: ListTile(leading: Icon(Icons.psychology, size: 20), title: Text('从 MBTI 创建', style: TextStyle(fontSize: 14)))),
            PopupMenuItem(value: 'emotion', child: ListTile(leading: Icon(Icons.favorite, size: 20), title: Text('情感模板', style: TextStyle(fontSize: 14)))),
            PopupMenuItem(value: 'custom', child: ListTile(leading: Icon(Icons.edit, size: 20), title: Text('自定义创建', style: TextStyle(fontSize: 14)))),
          ],
        ),
      ]),
      body: Consumer<PersonaService>(
        builder: (context, svc, _) {
          if (svc.personas.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(C.s32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.people_outline, size: 48, color: Color(0xFF5B5B65)),
                  const SizedBox(height: C.s16),
                  Text('创建你的第一个 AI 人格', style: C.title),
                  const SizedBox(height: C.s8),
                  Text('选择一种方式开始', style: C.caption),
                  const SizedBox(height: C.s24),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _emptyBtn(context, Icons.psychology, 'MBTI 人格', () => _showMbtiSheet(context)),
                    const SizedBox(width: C.s16),
                    _emptyBtn(context, Icons.favorite, '情感模板', () => _showEmotionSheet(context)),
                    const SizedBox(width: C.s16),
                    _emptyBtn(context, Icons.edit, '自定义', () => _edit(context, null)),
                  ]),
                ]),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(C.s16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: C.s8, crossAxisSpacing: C.s8, childAspectRatio: 0.85,
            ),
            itemCount: svc.personas.length,
            itemBuilder: (_, i) {
              final p = svc.personas[i];
              final sel = svc.selected?.id == p.id;
              return GestureDetector(
                onTap: () {
                  svc.selectAndSave(p.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已切换至「${p.name}」'), duration: const Duration(seconds: 1)),
                  );
                },
                onLongPress: () => _edit(context, p),
                child: Container(
                  decoration: BoxDecoration(
                    color: C.scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(C.r10),
                    border: Border.all(
                      color: sel ? const Color(0xFF7C3AED) : C.scheme.outlineVariant.withValues(alpha: 0.3),
                      width: sel ? 2 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.all(C.s12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(p.avatar, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: C.s8),
                    Text(p.name, style: C.title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: C.s4),
                    if (p.mbti.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: C.s8, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFEDE9FE), borderRadius: BorderRadius.circular(C.r6)),
                        child: Text(p.mbti, style: const TextStyle(fontSize: 10, color: Color(0xFF7C3AED), fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(height: C.s4),
                    Text(_toneLabel(p.tone), style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
                    if (sel)
                      Padding(
                        padding: const EdgeInsets.only(top: C.s4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF7C3AED))),
                          const SizedBox(width: C.s4),
                          const Text('使用中', style: TextStyle(fontSize: 10, color: Color(0xFF7C3AED))),
                        ]),
                      ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _emptyBtn(BuildContext ctx, IconData icon, String label, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80, padding: const EdgeInsets.all(C.s12),
        decoration: BoxDecoration(
          color: C.scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(C.r10),
          border: Border.all(color: C.scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(children: [
          Icon(icon, size: 24, color: C.scheme.primary),
          const SizedBox(height: C.s8),
          Text(label, style: C.caption, textAlign: TextAlign.center),
        ]),
      ),
    );

  String _toneLabel(String t) {
    switch (t) {
      case 'casual': return '随意';
      case 'humorous': return '幽默';
      case 'professional': return '专业';
      default: return '正式';
    }
  }

  void _showMbtiSheet(BuildContext ctx) {
    final templates = PersonaService.mbtiTemplates;
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(C.s16),
          children: [
            Text('选择 MBTI 人格', style: C.title),
            const SizedBox(height: C.s4),
            Text('一键创建 16 种 MBTI 人格，自动填充性格设定', style: C.caption),
            const SizedBox(height: C.s16),
            ...templates.map((t) => ListTile(
              leading: Text(t.avatar, style: const TextStyle(fontSize: 24)),
              title: Text(t.name, style: C.body),
              subtitle: Text(t.traits, style: C.caption),
              trailing: Text(t.mbti, style: C.label),
              onTap: () {
                ctx.read<PersonaService>().addFromTemplate(t);
                Navigator.pop(ctx);
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showEmotionSheet(BuildContext ctx) {
    final templates = PersonaService.emotionTemplates;
    showModalBottomSheet(
      context: ctx,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(C.s16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('选择情感模板', style: C.title),
          const SizedBox(height: C.s4),
          Text('5 种情感角色，满足不同的对话需求', style: C.caption),
          const SizedBox(height: C.s16),
          ...templates.map((t) => ListTile(
            leading: Text(t.avatar, style: const TextStyle(fontSize: 24)),
            title: Text(t.name, style: C.body),
            subtitle: Text(t.traits, maxLines: 1, overflow: TextOverflow.ellipsis, style: C.caption),
            trailing: Text(t.mbti, style: C.label),
            onTap: () {
              ctx.read<PersonaService>().addFromTemplate(t);
              Navigator.pop(ctx);
            },
          )),
          const SizedBox(height: C.s12),
        ]),
      ),
    );
  }

  void _edit(BuildContext ctx, Persona? existing) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final promptCtrl = TextEditingController(text: existing?.systemPrompt ?? '');
    final avatarCtrl = TextEditingController(text: existing?.avatar ?? '🤖');
    final customCtrl = TextEditingController(text: existing?.customExpertise ?? '');
    final traitsCtrl = TextEditingController(text: existing?.traits ?? '');
    double temp = existing?.temperature ?? 0.7;
    String replyLength = existing?.replyLength ?? 'normal';
    String tone = existing?.tone ?? 'professional';
    String language = existing?.language ?? 'zh';
    String expertise = existing?.expertise ?? 'general';
    String mbti = existing?.mbti ?? '';

    showDialog(
      context: ctx,
      builder: (c) => StatefulBuilder(
        builder: (c, setSt) => AlertDialog(
          title: Text(existing == null ? '新建人格' : '编辑人格'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: TextField(controller: nameCtrl, style: C.body, decoration: const InputDecoration(labelText: '名称'))),
                const SizedBox(width: C.s8),
                SizedBox(width: 60, child: TextField(controller: avatarCtrl, style: const TextStyle(fontSize: 22), decoration: const InputDecoration(labelText: '头像'), maxLength: 2, textAlign: TextAlign.center)),
              ]),
              const SizedBox(height: C.s8),
              TextField(controller: promptCtrl, style: C.body, maxLines: 3, decoration: const InputDecoration(labelText: 'System Prompt')),
              const SizedBox(height: C.s12),
              Text('温度', style: C.label),
              Row(children: [
                const Text('0', style: TextStyle(fontSize: 11)),
                Expanded(child: Slider(value: temp, min: 0.0, max: 1.5, divisions: 15, onChanged: (v) => setSt(() => temp = v))),
                const Text('1.5', style: TextStyle(fontSize: 11)),
              ]),
              Center(child: Text(temp.toStringAsFixed(1), style: C.title)),
              const SizedBox(height: C.s12),
              Text('回复长度', style: C.label),
              _chipSelector(Persona.replyLengthOptions, replyLength, (v) => setSt(() => replyLength = v)),
              const SizedBox(height: C.s12),
              Text('语气风格', style: C.label),
              _chipSelector(Persona.toneOptions, tone, (v) => setSt(() => tone = v)),
              const SizedBox(height: C.s12),
              Text('回复语言', style: C.label),
              _chipSelector(Persona.languageOptions, language, (v) => setSt(() => language = v)),
              const SizedBox(height: C.s12),
              Text('专业领域', style: C.label),
              _chipSelector(Persona.expertiseOptions, expertise, (v) => setSt(() => expertise = v)),
              if (expertise == 'custom')
                Padding(
                  padding: const EdgeInsets.only(top: C.s8),
                  child: TextField(controller: customCtrl, style: C.body, decoration: const InputDecoration(hintText: '描述 AI 擅长的领域...')),
                ),
              const SizedBox(height: C.s16),
              Text('MBTI 性格类型', style: C.label),
              const SizedBox(height: C.s4),
              Wrap(spacing: C.s8, runSpacing: C.s8, children: [
                GestureDetector(
                  onTap: () => setSt(() => mbti = ''),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: C.s12, vertical: C.s8),
                    decoration: BoxDecoration(
                      color: mbti.isEmpty ? C.scheme.primary.withValues(alpha: 0.15) : C.scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(C.s8),
                    ),
                    child: const Text('无', style: TextStyle(color: Color(0xFF5B5B65), fontSize: 12)),
                  ),
                ),
                ...Persona.mbtiTypes.map((t) {
                  final sel = mbti == t;
                  return GestureDetector(
                    onTap: () => setSt(() => mbti = t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: C.s12, vertical: C.s8),
                      decoration: BoxDecoration(
                        color: sel ? C.scheme.primary.withValues(alpha: 0.15) : C.scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(C.s8),
                        border: sel ? Border.all(color: C.scheme.primary.withValues(alpha: 0.3)) : null,
                      ),
                      child: Text(t, style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w600 : FontWeight.w400, color: sel ? C.scheme.primary : const Color(0xFFA1A1AA))),
                    ),
                  );
                }),
              ]),
              if (mbti.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: C.s4), child: Text(Persona.mbtiDescriptions[mbti] ?? '', style: C.caption)),
              const SizedBox(height: C.s12),
              Text('性格特质', style: C.label),
              const SizedBox(height: C.s4),
              TextField(controller: traitsCtrl, style: C.body, maxLines: 2,
                decoration: const InputDecoration(hintText: '例如：好奇心强、逻辑思维严谨、偶尔毒舌')),
              const SizedBox(height: C.s12),
              if (existing != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(c);
                    ctx.read<PersonaService>().delete(existing.id);
                  },
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                  label: const Text('删除此人格', style: TextStyle(color: Colors.red, fontSize: 13)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            ElevatedButton(onPressed: () {
              final svc = ctx.read<PersonaService>();
              if (existing == null) {
                svc.add(nameCtrl.text, promptCtrl.text, avatar: avatarCtrl.text, temp: temp);
                final p = svc.personas.last;
                svc.update(p.id, replyLength: replyLength, tone: tone, language: language,
                    expertise: expertise, customExpertise: customCtrl.text, mbti: mbti, traits: traitsCtrl.text);
              } else {
                svc.update(existing.id, name: nameCtrl.text, avatar: avatarCtrl.text,
                    systemPrompt: promptCtrl.text, temperature: temp,
                    replyLength: replyLength, tone: tone, language: language,
                    expertise: expertise, customExpertise: customCtrl.text, mbti: mbti, traits: traitsCtrl.text);
              }
              Navigator.pop(c);
            }, child: const Text('保存')),
          ],
        ),
      ),
    );
  }

  Widget _chipSelector(List<Map<String, String>> opts, String val, void Function(String) onSelect) {
    return Wrap(spacing: C.s8, runSpacing: C.s4, children: opts.map((o) {
      final sel = o['value'] == val;
      return GestureDetector(
        onTap: () => onSelect(o['value']!),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: C.s12, vertical: C.s8),
          decoration: BoxDecoration(
            color: sel ? C.scheme.primary.withValues(alpha: 0.15) : C.scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(C.r8),
            border: sel ? Border.all(color: C.scheme.primary.withValues(alpha: 0.3)) : null,
          ),
          child: Column(children: [
            Text(o['label']!, style: sel ? C.body.copyWith(fontWeight: FontWeight.w600) : C.body),
            Text(o['desc']!, style: C.caption),
          ]),
        ),
      );
    }).toList());
  }
}
