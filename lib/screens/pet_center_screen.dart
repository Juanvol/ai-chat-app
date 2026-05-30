// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'pet_chat_screen.dart';
import 'pet_memory_screen.dart';
import 'pet_diary_screen.dart';
import 'pet_settings_screen.dart';

class PetCenterScreen extends StatefulWidget {
  const PetCenterScreen({super.key});

  @override
  State<PetCenterScreen> createState() => _PetCenterScreenState();
}

class _PetCenterScreenState extends State<PetCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🐾 宠物中心'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _StatusCard(),
          _TokenDashboard(),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '💬 聊天'),
              Tab(text: '🧠 记忆'),
              Tab(text: '📖 日记'),
              Tab(text: '⚙️ 设置'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                PetChatScreen(),
                PetMemoryScreen(),
                PetDiaryScreen(),
                PetSettingsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Row(
              children: [
                Text('🐱', style: TextStyle(fontSize: 32)),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('弗糯糯',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('L3 活跃 · 初识',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
                Spacer(),
                Column(
                  children: [
                    Text('💕 320',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('好感度',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatItem(emoji: '😊', label: '开心'),
                _StatItem(emoji: '🍖', label: '饱了'),
                _StatItem(emoji: '⚡', label: '精神'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String emoji;
  final String label;
  const _StatItem({required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _TokenDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Text('📊', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('今日 0 / 50k', style: TextStyle(fontWeight: FontWeight.w500)),
            SizedBox(width: 16),
            Text('📈 本月 0', style: TextStyle(color: Colors.grey)),
            Spacer(),
            Text('剩余 50k', style: TextStyle(color: Colors.green)),
          ],
        ),
      ),
    );
  }
}
