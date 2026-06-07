// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/app/feedback_service.dart';
import '../utils/memory_extractor.dart';
import '../utils/page_routes.dart' show pushElastic;
import '../screens/feedback_screen.dart';

/// 聊天页顶部横幅：记忆提取提示 + 反馈进化提示
class HomeChatBanners {
  HomeChatBanners._();

  static Widget feedbackBanner(BuildContext context, FeedbackService fb,
      VoidCallback onClose) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(C.s16, C.s8, C.s16, 0),
      padding: const EdgeInsets.symmetric(horizontal: C.s12, vertical: C.s8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withAlpha(60),
        borderRadius: BorderRadius.circular(C.r8),
        border: Border.all(color: scheme.primary.withAlpha(80)),
      ),
      child: Row(children: [
        const Text('✨', style: TextStyle(fontSize: 14)),
        const SizedBox(width: C.s8),
        Expanded(
          child: Text('AI 已根据你的 ${fb.processedCount} 条反馈进化',
              style: C.caption(context).copyWith(color: scheme.primary)),
        ),
        GestureDetector(
          onTap: () {
            fb.markAdjustmentSeen();
            pushElastic(context, const FeedbackScreen());
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: C.s8),
            child: Text('查看',
                style: TextStyle(fontSize: 13, color: scheme.primary, fontWeight: FontWeight.w500)),
          ),
        ),
        GestureDetector(
          onTap: onClose,
          child: Icon(Icons.close, size: 14, color: scheme.primary),
        ),
      ]),
    );
  }

  static Widget memoryBanner(BuildContext context, VoidCallback onExtract,
      VoidCallback onClose) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(C.s16, C.s8, C.s16, 0),
      padding: const EdgeInsets.symmetric(horizontal: C.s12, vertical: C.s8),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withAlpha(60),
        borderRadius: BorderRadius.circular(C.r8),
        border: Border.all(color: scheme.tertiary.withAlpha(80)),
      ),
      child: Row(children: [
        Icon(Icons.auto_awesome, size: 15, color: scheme.tertiary),
        const SizedBox(width: C.s8),
        Expanded(
          child: Text('检测到可保存的任务上下文',
              style: C.caption(context).copyWith(color: scheme.tertiary)),
        ),
        GestureDetector(
          onTap: onExtract,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: C.s8),
            child: Text('提取',
                style: TextStyle(fontSize: 13, color: scheme.tertiary, fontWeight: FontWeight.w500)),
          ),
        ),
        GestureDetector(
          onTap: onClose,
          child: Icon(Icons.close, size: 14, color: scheme.tertiary),
        ),
      ]),
    );
  }

  /// 执行记忆提取，显示 loading + 结果 snackbar
  static Future<void> doExtractMemories(BuildContext context) async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final added = await extractMemories(context);
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(added > 0
                ? '已提取 $added 条上下文'
                : '未检测到可提取的信息')),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('提取失败: $e')));
    }
  }
}
