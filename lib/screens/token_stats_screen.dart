// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/model_config.dart';
import '../services/app/token_stats_service.dart';

class TokenStatsScreen extends StatelessWidget {
  const TokenStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<TokenStatsService>();
    final stats = svc.dailyStats(7);
    final maxTokens = stats.fold<int>(0, (m, s) => s.tokens > m ? s.tokens : m);
    final maxBar = maxTokens > 0 ? maxTokens : 1;

    return Scaffold(
      appBar: AppBar(title: const Text('用量统计')),
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: C.s16, vertical: C.s12), children: [
        // 总览卡片
        _section('总览'),
        const SizedBox(height: C.s8),
        Container(
          padding: const EdgeInsets.all(C.s16),
          decoration: _cardDeco(),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _statCol('总 Token', svc.totalTokens, C.scheme.primary),
              _statCol('请求次数', svc.usages.length, C.scheme.primary),
              _statCol('模型数', svc.usageByModel.length, C.scheme.primary),
            ]),
            const SizedBox(height: C.s16),
            Text('预估总费用 ¥${svc.totalCostCNY.toStringAsFixed(4)}',
              style: C.title.copyWith(color: C.scheme.primary)),
          ]),
        ),

        const SizedBox(height: C.s20),

        // 每日用量柱状图
        _section('近 7 日用量'),
        const SizedBox(height: C.s8),
        Container(
          padding: const EdgeInsets.only(top: C.s16, left: C.s8, right: C.s8, bottom: C.s8),
          decoration: _cardDeco(),
          child: Column(children: [
            SizedBox(
              height: 160,
              child: CustomPaint(
                size: const Size(double.infinity, 160),
                painter: _BarChartPainter(stats: stats, maxTokens: maxBar.toDouble()),
              ),
            ),
            const SizedBox(height: C.s4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: stats.map((s) => SizedBox(
                width: 30,
                child: Text('${s.date.month}/${s.date.day}', style: const TextStyle(fontSize: 10)),
              )).toList(),
            ),
          ]),
        ),

        const SizedBox(height: C.s20),

        // 按模型费用
        _section('按模型费用'),
        const SizedBox(height: C.s8),
        ...svc.usageByModel.entries.map((entry) {
          final model = ModelConfig.builtIn.where((m) => m.id == entry.key).firstOrNull;
          final cost = svc.costForModel(entry.key);
          final tokens = entry.value.fold<int>(0, (s, u) => s + u.totalTokens);
          return Container(
            margin: const EdgeInsets.only(bottom: C.s8),
            padding: const EdgeInsets.all(C.s12),
            decoration: _cardDeco(),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(model?.name ?? entry.key, style: C.body),
                const SizedBox(height: 2),
                Text('${entry.value.length} 次 · $tokens tokens', style: C.caption),
              ])),
              Text('¥${cost.toStringAsFixed(4)}', style: C.title),
            ]),
          );
        }),

        if (svc.usageByModel.isEmpty)
          Padding(
            padding: const EdgeInsets.all(C.s32),
            child: Center(child: Text('暂无用量数据', style: C.caption)),
          ),

        const SizedBox(height: C.s20),

        // 汇总
        if (svc.usages.isNotEmpty) ...[
          _section('用量明细'),
          const SizedBox(height: C.s8),
          Container(
            padding: const EdgeInsets.all(C.s12),
            decoration: _cardDeco(),
            child: Column(children: [
              _detailRow('提示 Token', svc.totalPromptTokens),
              _detailRow('补全 Token', svc.totalCompletionTokens),
              _detailRow('总计', svc.totalTokens),
              const Divider(height: C.s16),
              _detailRow('预估费用（人民币）', '¥${svc.totalCostCNY.toStringAsFixed(4)}'),
            ]),
          ),
        ],

        const SizedBox(height: C.s32),
      ]),
    );
  }

  Widget _section(String t) => Text(t, style: C.label);

  Widget _statCol(String label, int value, Color color) => Column(children: [
    Text(value.toString(), style: C.h2.copyWith(color: color)),
    const SizedBox(height: 2),
    Text(label, style: C.caption),
  ]);

  Widget _detailRow(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: C.caption),
      Text(value.toString(), style: C.body),
    ]),
  );

  BoxDecoration _cardDeco() => BoxDecoration(
    color: C.scheme.surface,
    borderRadius: BorderRadius.circular(C.r10),
    border: Border.all(color: C.scheme.outlineVariant.withValues(alpha: 0.3)),
  );
}

class _BarChartPainter extends CustomPainter {
  final List<({DateTime date, int tokens, int count})> stats;
  final double maxTokens;

  _BarChartPainter({required this.stats, required this.maxTokens});

  @override
  void paint(Canvas canvas, Size size) {
    if (stats.isEmpty) return;
    final barW = (size.width / stats.length) * 0.6;
    final gap = size.width / stats.length;
    final paint = Paint()
      ..color = C.scheme.primaryContainer
      ..style = PaintingStyle.fill;

    for (var i = 0; i < stats.length; i++) {
      final h = maxTokens > 0 ? (stats[i].tokens / maxTokens) * (size.height - 20) : 0.0;
      final x = gap * i + (gap - barW) / 2;
      final y = size.height - h - 16;
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(x, y, barW, h > 0 ? h : 1),
          topLeft: const Radius.circular(3), topRight: const Radius.circular(3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.maxTokens != maxTokens || old.stats != stats;
}
