// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../../pet/pet_persona.dart';
import '../../services/pet/persona/persona_store.dart';

/// 人格设置 — V3: 气泡预览 + 卡片选人格 + emoji 滑块 + 保存
class PetPersonaScreen extends StatefulWidget {
  final PersonaStore personaStore;
  const PetPersonaScreen({super.key, required this.personaStore});

  @override
  State<PetPersonaScreen> createState() => _PetPersonaScreenState();
}

class _PetPersonaScreenState extends State<PetPersonaScreen> {
  late TextEditingController _name, _selfRef, _ending, _prompt;
  late PersonalityTraits _traits;
  bool _dirty = false, _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.personaStore.persona;
    _name = TextEditingController(text: p.name);
    _selfRef = TextEditingController(text: p.style.selfReference);
    _ending = TextEditingController(text: p.style.sentenceEnding);
    _prompt = TextEditingController(text: p.systemPrompt);
    _traits = p.personalityTraits;
  }

  @override
  void dispose() {
    _name.dispose(); _selfRef.dispose();
    _ending.dispose(); _prompt.dispose();
    super.dispose();
  }

  void _mark() { if (!_dirty) setState(() => _dirty = true); }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.personaStore.save(PetPersona(
        name: _name.text.trim(),
        personalityTraits: _traits,
        style: const SpeakingStyle().copyWith(
          selfReference: _selfRef.text.trim(),
          sentenceEnding: _ending.text.trim(),
        ),
        systemPrompt: _prompt.text.trim(),
        source: 'user_custom',
      ));
      if (mounted) {
        setState(() { _saving = false; _dirty = false; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)));
      }
    } catch (e) {
      if (mounted) { setState(() => _saving = false); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存失败'), duration: Duration(seconds: 2))); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _name.text.isEmpty && _selfRef.text.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('性格调整'),
        actions: [TextButton(onPressed: _dirty && !_saving ? _save : null, child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold)))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        physics: const BouncingScrollPhysics(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ═══ 气泡预览 ═══
          Center(child: Column(children: [
            Container(width: 56, height: 56, decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF2D1B69), Color(0xFF4C1D95)]),
              borderRadius: BorderRadius.circular(16),
            ), child: const Center(child: Text('🐱', style: TextStyle(fontSize: 28)))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF1E1E35), borderRadius: BorderRadius.circular(16)),
              child: Text(isNew ? '我还没有名字...\n快去设置一个吧~ ✨' : '我是 ${_name.text.isEmpty ? '???' : _name.text}，\n${_selfRef.text.isEmpty ? '还没有自称' : _selfRef.text}最喜欢和主人待在一起~ ${_ending.text}',
                style: const TextStyle(color: Color(0xFFD0D0E8), fontSize: 13, height: 1.6)),
            ),
          ])),
          const SizedBox(height: 20),

          // ═══ 基本设定 ═══
          Text('基本设定', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _inp('名字', _name)),
            const SizedBox(width: 8),
            Expanded(child: _inp('自称', _selfRef)),
            const SizedBox(width: 8),
            Expanded(child: _inp('句尾', _ending)),
          ]),
          const SizedBox(height: 20),

          // ═══ System Prompt ═══
          Text('人格提示词', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          Text('通过提示词设定宠物的性格、说话方式、行为习惯', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          TextField(controller: _prompt, maxLines: 5, minLines: 3,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFFBBBBBB)),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(10),
              hintText: '输入 System Prompt...',
            ),
            onChanged: (_) => _mark(),
          ),
        ]),
      ),
    );
  }

  Widget _inp(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(fontSize: 14, color: Color(0xFFE0E0F0)),
      decoration: InputDecoration(
        labelText: label, isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        hintText: label == '名字' ? '给你的宠物取个名' : label == '自称' ? '如：本喵' : '如：喵~',
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF444444)),
      ),
      onChanged: (_) => _mark(),
    );
  }
}
