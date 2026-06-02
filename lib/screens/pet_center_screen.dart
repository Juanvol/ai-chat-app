// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../widgets/pet_hero_card.dart';
import '../widgets/pet_status_bars.dart';
import '../widgets/pet_action_bar.dart';
import '../widgets/pet_info_chips.dart';
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

  void _switchToChat() => _tabController.animateTo(0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🐾 宠物中心'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const PetHeroCard(),
          const PetStatusBars(),
          PetActionBar(onChat: _switchToChat),
          const PetInfoChips(),
          const SizedBox(height: 4),
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
