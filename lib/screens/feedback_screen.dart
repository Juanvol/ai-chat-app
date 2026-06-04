import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/model_config.dart';
import '../services/app/conversation_service.dart';
import '../services/app/feedback_service.dart';

class FeedbackScreen extends StatelessWidget {
  const FeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Hero(tag: 'hero_title_反馈知识库', child: Text('反馈知识库')), actions: [
        IconButton(icon: const Icon(Icons.add, size: 20), onPressed: () => _addManual(context)),
      ]),
      body: Consumer<FeedbackService>(
        builder: (context, svc, _) {
          final adjVersions = svc.adjustmentVersions;
          return Column(children: [
            // 进化摘要卡片
            if (svc.evolutionCount > 0)
              Container(
                margin: const EdgeInsets.all(C.s16),
                padding: const EdgeInsets.all(C.s12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(C.r10),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('AI 已在为你进化', style: C.title(context).copyWith(color: Theme.of(context).colorScheme.primary)),
                    const Spacer(),
                    if (svc.lastAnalysisTime != null)
                      Text('${svc.lastAnalysisTime!.month}/${svc.lastAnalysisTime!.day} 分析', style: C.label(context)),
                  ]),
                  const SizedBox(height: C.s8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _statCol('${svc.processedCount}', '已处理', Theme.of(context).colorScheme.primary, context),
                    _statCol('${svc.evolutionCount}', '次进化', Theme.of(context).colorScheme.primary, context),
                    _statCol('${svc.unprocessedCount}', '待分析', Theme.of(context).colorScheme.primary, context),
                  ]),
                  const SizedBox(height: C.s12),
                  Container(
                    padding: const EdgeInsets.all(C.s12),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(C.r8)),
                    child: Text('当前修正：${svc.adjustmentText.length > 80 ? '${svc.adjustmentText.split('\n---\n').last.replaceAll('\n', ' · ').substring(0, 80)}...' : svc.adjustmentText.replaceAll('\n', ' · ')}',
                      style: C.caption(context).copyWith(height: 1.4)),
                  ),
                  const SizedBox(height: C.s8),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton.icon(
                      onPressed: svc.isAnalyzing ? null : () => _autoAnalyze(context, svc),
                      icon: svc.isAnalyzing
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                          : Icon(Icons.auto_awesome, size: 13, color: Theme.of(context).colorScheme.primary),
                      label: Text(svc.isAnalyzing ? '分析中...' : 'AI 分析',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
                    ),
                    TextButton.icon(
                      onPressed: () => _editAdjustment(context, svc),
                      icon: Icon(Icons.edit, size: 13, color: Theme.of(context).colorScheme.primary),
                      label: Text('编辑', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
                    ),
                  ]),
                ]),
              ),

            // 进化时间线
            if (adjVersions.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: C.s16),
                child: Row(children: [
                  Text('进化历程', style: C.label(context)),
                  const Spacer(),
                ]),
              ),
              const SizedBox(height: C.s4),
              SizedBox(
                height: (adjVersions.length * 72.0).clamp(0, 220),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: C.s16),
                  itemCount: adjVersions.length,
                  itemBuilder: (_, i) {
                    final v = adjVersions[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: C.s8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Column(children: [
                          Container(width: 10, height: 10,
                            decoration: BoxDecoration(shape: BoxShape.circle,
                              color: i == 0 ? const Color(0xFF7C3AED) : const Color(0xFFA78BFA))),
                          if (i < adjVersions.length - 1)
                            Container(width: 2, height: 40, color: const Color(0xFFE5E7EB)),
                        ]),
                        const SizedBox(width: C.s12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(C.s12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(C.r8),
                            ),
                            child: Text(v.content, style: C.caption(context).copyWith(height: 1.4)),
                          ),
                        ),
                      ]),
                    );
                  },
                ),
              ),
            ],

            const Divider(height: 1),

            // 反馈列表
            Padding(
              padding: const EdgeInsets.all(C.s16),
              child: Row(children: [
                Text('反馈记录 (${svc.entries.length})', style: C.title(context)),
                const Spacer(),
                if (svc.unprocessedCount > 0)
                  Text('${svc.unprocessedCount} 条未处理', style: C.label(context)),
              ]),
            ),

            Expanded(
              child: svc.entries.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.feedback_outlined, size: 36, color: Color(0xFF5B5B65)),
                        const SizedBox(height: C.s8),
                        Text('暂无反馈', style: C.caption(context)),
                      ]),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: C.s16),
                      itemCount: svc.entries.length,
                      itemBuilder: (_, i) {
                        final e = svc.entries[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: C.s8),
                          padding: const EdgeInsets.all(C.s12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(C.r8),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: C.s8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: e.processed
                                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                                      : Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(C.r6),
                                ),
                                child: Text(e.processed ? '已处理' : '未处理',
                                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface)),
                              ),
                              const Spacer(),
                              Text(e.reason, style: C.label(context)),
                            ]),
                            const SizedBox(height: C.s8),
                            Text('提问: ${e.userMessage}', style: C.caption(context)),
                            const SizedBox(height: C.s4),
                            Text('回答: ${e.aiResponse.length > 80 ? '${e.aiResponse.substring(0, 80)}...' : e.aiResponse}',
                              style: C.body(context)),
                            if (e.adjustmentResult != null) ...[
                              const SizedBox(height: C.s8),
                              Text('修正: ${e.adjustmentResult}', style: C.caption(context).copyWith(color: Theme.of(context).colorScheme.primary)),
                            ],
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

  Widget _statCol(String value, String label, Color color, BuildContext context) => Column(children: [
    Text(value, style: C.h2(context).copyWith(color: color)),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
  ]);

  void _addManual(BuildContext ctx) {
    final userCtrl = TextEditingController();
    final aiCtrl = TextEditingController();
    String reason = '不满意';
    showDialog(
      context: ctx,
      builder: (c) => StatefulBuilder(
        builder: (c, setSt) => AlertDialog(
          title: const Text('手动添加反馈'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: userCtrl, style: C.body(ctx), maxLines: 2, decoration: const InputDecoration(labelText: '用户提问')),
              const SizedBox(height: C.s8),
              TextField(controller: aiCtrl, style: C.body(ctx), maxLines: 3, decoration: const InputDecoration(labelText: 'AI 回答')),
              const SizedBox(height: C.s12),
              Text('原因', style: C.label(ctx)),
              Wrap(spacing: C.s8, children: ['不满意', '不准确', '跑题', '太啰嗦', '太简短', '格式差'].map((r) => ChoiceChip(
                label: Text(r, style: const TextStyle(fontSize: 12)),
                selected: reason == r,
                onSelected: (_) => setSt(() => reason = r),
                selectedColor: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.2),
              )).toList()),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            ElevatedButton(onPressed: () {
              if (userCtrl.text.isNotEmpty && aiCtrl.text.isNotEmpty) {
                ctx.read<FeedbackService>().add(
                  conversationId: 'manual',
                  userMessage: userCtrl.text,
                  aiResponse: aiCtrl.text,
                  reason: reason,
                );
              }
              Navigator.pop(c);
            }, child: const Text('添加')),
          ],
        ),
      ),
    );
  }

  void _autoAnalyze(BuildContext ctx, FeedbackService svc) async {
    final cs = ctx.read<ConversationService>();
    final model = ModelConfig.builtIn.firstWhere((m) => m.id == cs.storage.selModel, orElse: () => ModelConfig.builtIn.first);
    final provider = ModelConfig.providers.firstWhere((p) => p.id == model.providerId, orElse: () => ModelConfig.providers.first);
    await svc.autoGenerate(
      client: cs.client,
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey.isNotEmpty ? provider.apiKey : null,
      model: model.modelId,
    );
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('AI 分析完成'), duration: Duration(seconds: 1)));
    }
  }

  void _editAdjustment(BuildContext ctx, FeedbackService svc) {
    final ctrl = TextEditingController(text: svc.adjustmentText);
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('AI 自我修正指令'),
        content: TextField(controller: ctrl, style: C.body(ctx), maxLines: 8,
          decoration: const InputDecoration(hintText: '编写 AI 行为修正指令...\n例如：回答不要太啰嗦，直接给代码')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          ElevatedButton(onPressed: () { svc.saveAdjustmentText(ctrl.text); Navigator.pop(c); }, child: const Text('保存')),
        ],
      ),
    );
  }
}
