// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';

class HomeMessageMenu extends StatelessWidget {
  final bool isUser;
  final bool isLastAi;
  final VoidCallback onCopy;
  final VoidCallback onRegenerate;
  final VoidCallback? onDislike;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const HomeMessageMenu({
    super.key,
    required this.isUser,
    required this.isLastAi,
    required this.onCopy,
    required this.onRegenerate,
    this.onDislike,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('消息操作'),
      children: [
        _item(Icons.copy, '复制', onCopy),
        if (isLastAi && !isUser)
          _item(Icons.refresh, '重新生成', onRegenerate),
        if (isLastAi && !isUser && onDislike != null)
          _item(Icons.thumb_down_outlined, '踩', onDislike!),
        if (isUser && onEdit != null)
          _item(Icons.edit, '编辑', onEdit!),
        if (onDelete != null) _item(Icons.delete_outline, '删除', onDelete!),
      ],
    );
  }

  Widget _item(IconData icon, String label, VoidCallback onTap) {
    return SimpleDialogOption(
      onPressed: onTap,
      child:
          Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)]),
    );
  }
}
