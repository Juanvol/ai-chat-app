import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/conversation_service.dart';
import '../services/memory_service.dart';
import '../utils/memory_extractor.dart';

const _impLabels = ['', '临时提及', '技术约束', '已做决策', '当前任务', '核心目标'];
const _impColors = [Colors.transparent, Color(0xFF94A3B8), Color(0xFF60A5FA), Color(0xFF34D399), Color(0xFFF59E0B), Color(0xFF7C3AED)];

class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('任务上下文'), actions: [
        IconButton(icon: const Icon(Icons.auto_awesome_outlined, size: 18), tooltip: '从当前对话提取任务上下文', onPressed: () => _extractFromChat(context)),
        const SizedBox(width: C.s4),
        IconButton(icon: const Icon(Icons.add, size: 20), onPressed: () => _edit(context, null)),
      ]),
      body: Consumer<MemoryService>(
        builder: (context, svc, _) {
          if (svc.memories.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(C.s32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.work_outline, size: 40, color: Color(0xFF5B5B65)),
                  const SizedBox(height: C.s12),
                  Text('任务上下文', style: C.title),
                  const SizedBox(height: C.s8),
                  Text('记录你正在做的事、目标和决策，帮助 AI 更精准地理解你的问题。', style: C.caption, textAlign: TextAlign.center),
                  const SizedBox(height: C.s20),
                  _importanceLegend(),
                  const SizedBox(height: C.s20),
                  ElevatedButton.icon(
                    onPressed: () => _edit(context, null),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('添加第一条上下文'),
                  ),
                ]),
              ),
            );
          }
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(C.s12),
              child: _importanceLegend(),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: C.s16),
                itemCount: svc.memories.length,
                itemBuilder: (_, i) {
                  final m = svc.memories[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: C.s8),
                    padding: const EdgeInsets.all(C.s12),
                    decoration: BoxDecoration(
                      color: C.scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(C.r8),
                      border: Border(left: BorderSide(color: _impColors[m.importance], width: 3)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: C.s8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _impColors[m.importance].withOpacity(0.15),
                            borderRadius: BorderRadius.circular(C.r6),
                          ),
                          child: Text(_impLabels[m.importance],
                            style: TextStyle(fontSize: 11, color: _impColors[m.importance])),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _edit(context, m),
                          child: const Padding(padding: EdgeInsets.all(C.s8), child: Icon(Icons.edit, size: 15, color: Color(0xFF5B5B65))),
                        ),
                        GestureDetector(
                          onTap: () => svc.delete(m.id),
                          child: const Padding(padding: EdgeInsets.all(C.s8), child: Icon(Icons.close, size: 15, color: Color(0xFF5B5B65))),
                        ),
                      ]),
                      const SizedBox(height: C.s8),
                      Text(m.content, style: C.body),
                    ]),
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _importanceLegend() {
    return Container(
      padding: const EdgeInsets.all(C.s8),
      decoration: BoxDecoration(
        color: C.scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(C.r8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('重要度说明', style: C.label),
        const SizedBox(height: C.s4),
        Wrap(
          spacing: C.s8,
          runSpacing: C.s4,
          children: List.generate(5, (i) {
            final lvl = i + 1;
            return Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _impColors[lvl])),
              const SizedBox(width: C.s4),
              Text('$lvl=${_impLabels[lvl]}', style: C.label),
            ]);
          }),
        ),
      ]),
    );
  }

  void _edit(BuildContext ctx, dynamic m) {
    final ctrl = TextEditingController(text: m?.content ?? '');
    int imp = m?.importance ?? 3;
    showDialog(
      context: ctx,
      builder: (c) => StatefulBuilder(
        builder: (c, setSt) => AlertDialog(
          title: Text(m == null ? '添加上下文' : '编辑上下文'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctrl, style: C.body, maxLines: 3,
              decoration: const InputDecoration(hintText: '例如：正在用 Flutter 开发 AI Chat，当前在实现任务上下文功能')),
            const SizedBox(height: C.s12),
            Text('重要度', style: C.label),
            const SizedBox(height: C.s8),
            ...List.generate(5, (i) {
              final lvl = i + 1;
              return RadioListTile<int>(
                value: lvl, groupValue: imp,
                onChanged: (v) => setSt(() => imp = v!),
                title: Row(children: [
                  Text('$lvl', style: C.title),
                  const SizedBox(width: C.s8),
                  Container(width: 10, height: 10,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: _impColors[lvl])),
                  const SizedBox(width: C.s8),
                  Text(_impLabels[lvl], style: C.body),
                  const SizedBox(width: C.s8),
                  Text(_impDesc(lvl), style: C.caption),
                ]),
                dense: true, contentPadding: EdgeInsets.zero,
              );
            }),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            ElevatedButton(onPressed: () {
              ctx.read<MemoryService>().add(ctrl.text, importance: imp);
              Navigator.pop(c);
              if (m != null) ctx.read<MemoryService>().delete(m.id);
            }, child: const Text('保存')),
          ],
        ),
      ),
    );
  }

  void _extractFromChat(BuildContext ctx) async {
    final cs = ctx.read<ConversationService>();
    final cov = cs.currentConversation;
    if (cov == null || cov.messages.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('当前没有对话内容')));
      return;
    }
    showDialog(context: ctx, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    try {
      final added = await extractMemories(ctx);
      Navigator.pop(ctx);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(added > 0 ? '已提取 $added 条上下文' : 'AI 未能提取到有效信息')));
      }
    } catch (e) {
      Navigator.pop(ctx);
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('提取失败: $e')));
    }
  }

  String _impDesc(int lvl) {
    switch (lvl) {
      case 1: return '可能相关';
      case 2: return '环境限制';
      case 3: return '已定方向';
      case 4: return '正在解决';
      case 5: return '长期目标';
      default: return '';
    }
  }
}
