// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/message.dart';
import '../services/app/conversation_service.dart';
import '../services/app/memory_service.dart';
import '../services/app/persona_service.dart';
import '../services/app/feedback_service.dart';
import '../services/pet/pet_logger.dart';

/// 聊天页弹窗：消息菜单、编辑、删除、反馈
class HomeChatDialogs {
  HomeChatDialogs._();

  /// 长按消息弹出菜单
  static void showMessageMenu(
    BuildContext context,
    Message msg,
    int index,
    Offset globalPosition, {
    required VoidCallback onRegenerate,
    required void Function(String, String) onDislike,
    required void Function(Message, int) onEdit,
    required VoidCallback onDelete,
  }) {
    if (msg.isStreaming) return;
    final isUser = msg.role == 'user';

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          globalPosition.dx, globalPosition.dy,
          globalPosition.dx + 1, globalPosition.dy + 1),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('复制')),
        if (!isUser) ...[
          const PopupMenuItem(value: 'regenerate', child: Text('重新生成')),
          const PopupMenuItem(value: 'feedback', child: Text('反馈 / 踩')),
        ],
        if (isUser)
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
        const PopupMenuItem(
            value: 'delete',
            child: Text('删除', style: TextStyle(color: Color(0xFFE53E3E)))),
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      PetLogger().info('Home', 'messageMenu: $value on msg#$index');
      switch (value) {
        case 'copy':
          Clipboard.setData(ClipboardData(text: msg.content));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
          );
        case 'regenerate':
          onRegenerate();
        case 'feedback':
          onDislike(msg.content, msg.content);
        case 'edit':
          onEdit(msg, index);
        case 'delete':
          onDelete();
      }
    });
  }

  /// 踩/AI 反馈弹窗
  static void showDislikeDialog(
    BuildContext ctx,
    String covId,
    String userMsg,
    String aiMsg,
  ) {
    String reason = '不满意';
    showDialog(
      context: ctx,
      builder: (c) => StatefulBuilder(
        builder: (c, setSt) => AlertDialog(
          title: const Text('记录反馈'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI 回答', style: C.label(ctx)),
              const SizedBox(height: C.s4),
              Text(
                  aiMsg.length > 120 ? '${aiMsg.substring(0, 120)}...' : aiMsg,
                  style: C.caption(ctx)),
              const SizedBox(height: C.s16),
              Text('原因', style: C.label(ctx)),
              const SizedBox(height: C.s8),
              Wrap(
                spacing: C.s8,
                runSpacing: C.s8,
                children: [
                  '不满意', '不准确', '跑题', '太啰嗦', '太简短', '格式差', '语义不明'
                ].map((r) => ChoiceChip(
                      label: Text(r, style: const TextStyle(fontSize: 12)),
                      selected: reason == r,
                      onSelected: (_) => setSt(() => reason = r),
                      selectedColor: const Color(0xFFD6E8FB),
                    )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            ElevatedButton(
              onPressed: () {
                ctx.read<FeedbackService>().add(
                      conversationId: covId,
                      userMessage: userMsg,
                      aiResponse: aiMsg,
                      reason: reason,
                    );
                Navigator.pop(c);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('已记录「$reason」。前往反馈知识库 → AI 分析 可生成修正指令'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
  }

  /// 编辑用户消息
  static void showEditDialog(BuildContext context, Message msg, int index,
      ConversationService svc) {
    final ctrl = TextEditingController(text: msg.content);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          style: C.body(context),
          decoration: const InputDecoration(hintText: '编辑后重新发送'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(c);
              final newContent = ctrl.text.trim();
              if (newContent.isEmpty) return;
              final cov = svc.currentConversation;
              if (cov == null) return;
              final msgs = cov.messages;
              if (index + 1 < msgs.length &&
                  msgs[index + 1].role == 'assistant') {
                msgs.removeAt(index + 1);
              }
              msgs.removeAt(index);
              final memSvc = context.read<MemoryService>();
              final perSvc = context.read<PersonaService>();
              final fbSvc = context.read<FeedbackService>();
              svc.sendMessage(newContent,
                memoryText: memSvc.promptText,
                personaPrompt: perSvc.selected?.fullPrompt,
                adjustmentText: fbSvc.adjustmentText,
                modelId: svc.storage.selModel,
                maxTokens: svc.globalMaxTokens,
              );
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
  }

  /// 删除消息确认
  static void showDeleteDialog(BuildContext context, int index,
      ConversationService svc, VoidCallback onDeleted) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('确定删除这条消息？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              final cov = svc.currentConversation;
              if (cov == null) return;
              cov.messages.removeAt(index);
              cov.updatedAt = DateTime.now();
              svc.storage.saveConv(cov);
              onDeleted();
            },
            child: const Text('删除', style: TextStyle(color: Color(0xFFE53E3E))),
          ),
        ],
      ),
    );
  }
}
