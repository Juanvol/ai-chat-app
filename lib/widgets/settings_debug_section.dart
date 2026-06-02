// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/pet_logger.dart';

class SettingsDebugSection extends StatelessWidget {
  final Future<String?> Function() onGetLogContent;
  final void Function(String text, File? file) onShare;
  final void Function(String text) onCopyClipboard;
  final Future<File?> Function() onExportTxt;
  final Future<void> Function() onClear;

  const SettingsDebugSection({
    super.key,
    required this.onGetLogContent,
    required this.onShare,
    required this.onCopyClipboard,
    required this.onExportTxt,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📋 调试日志',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('导出日志文件发送给开发者分析',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.6))),
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton.icon(
              onPressed: () => _exportLog(context),
              icon: const Icon(Icons.share, size: 16),
              label: const Text('导出日志'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () async { await onClear(); },
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('清空日志'),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _exportLog(BuildContext context) async {
    final content = await onGetLogContent();
    if (content == null || content.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无日志内容')),
        );
      }
      return;
    }
    onCopyClipboard(content);
    File? txtFile;
    try { txtFile = await onExportTxt(); } catch (_) {}
    onShare(content, txtFile);
  }
}
