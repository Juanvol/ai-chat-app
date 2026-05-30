// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';

class PetMemoryScreen extends StatelessWidget {
  const PetMemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🧠', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('还没有记忆，去和糯糯聊天或分享对话吧~',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              // Full integration in Phase 6
            },
            icon: const Icon(Icons.file_download),
            label: const Text('导入对话记忆'),
          ),
        ],
      ),
    );
  }
}
