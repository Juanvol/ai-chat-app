// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../pet/pet_controller.dart';
import '../../services/pet/pet_overlay_host.dart';
import 'pet_chat_screen.dart';
import 'pet_suggestion_screen.dart';
import 'pet_record_screen.dart';
import 'pet_settings_screen.dart';

class PetCenterScreen extends StatefulWidget {
  const PetCenterScreen({super.key});

  @override
  State<PetCenterScreen> createState() => _PetCenterScreenState();
}

class _PetCenterScreenState extends State<PetCenterScreen> {
  int _currentIndex = 0;

  static const _tabs = [
    (icon: '💬', label: '聊天'),
    (icon: '💡', label: '建议'),
    (icon: '📋', label: '记录'),
    (icon: '⚙️', label: '设置'),
  ];

  @override
  void initState() {
    super.initState();
    // 一进宠物中心就初始化知识库，不依赖宠物开关
    petOverlayController.ensureKB();
  }

  String _moodEmoji(double mood) {
    if (mood >= 80) return '😄';
    if (mood >= 50) return '😊';
    if (mood >= 20) return '😐';
    return '😢';
  }

  String _levelName(int interactions) {
    if (interactions < 30) return 'Lv.1';
    if (interactions < 200) return 'Lv.2';
    if (interactions < 1000) return 'Lv.3';
    return 'Lv.4';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── 顶栏：状态行 ──
            Consumer<PetController>(
              builder: (context, ctrl, _) =>
                  _buildHeader(context, ctrl),
            ),
            const Divider(height: 1),
            // ── 页面内容 ──
            // 各 Tab 内部已通过 kbReady.addListener 自行监听就绪事件，
            // 无需外层 ListenableBuilder（避免每次 kbReady 变化触发 4 个 Tab 全部 rebuild）
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: const [
                  PetChatScreen(),
                  PetSuggestionScreen(),
                  PetRecordScreen(),
                  PetSettingsScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Text(t.icon, style: const TextStyle(fontSize: 20)),
              label: t.label,
            ),
        ],
      ),
    );
  }

  // ── 状态行 ──

  Widget _buildHeader(BuildContext context, PetController ctrl) {
    final s = ctrl.state;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // 宠物图标 + 名字 + 等级
          const Icon(Icons.pets, size: 22, color: Color(0xFF8EC8B0)),
          const SizedBox(width: 6),
          Text(() {
                final p = petOverlayController.personaStore?.persona;
                if (p != null && p.name.isNotEmpty) return p.name;
                if (p != null && p.style.selfReference.isNotEmpty) return p.style.selfReference;
                return '未命名';
              }(),
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB8935D))),
          const SizedBox(width: 6),
          ColoredBox(
            color: const Color(0xFFB8935D),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              child: Text(
                _levelName(s.totalInteractions),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const Spacer(),
          // 迷你状态
          _MiniStat(emoji: '🍖', value: s.hunger, color: Colors.green),
          const SizedBox(width: 8),
          _MiniStat(
              emoji: _moodEmoji(s.mood),
              value: s.mood.toInt(),
              color: Colors.red),
          const SizedBox(width: 8),
          _MiniStat(emoji: '⚡', value: s.energy, color: Colors.amber),
          const SizedBox(width: 8),
          _MiniStat(
              emoji: '❤️',
              value: s.affection ~/ 10,
              color: Colors.pink),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────
// _MiniStat
// ────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String emoji;
  final int value;
  final Color color;

  const _MiniStat(
      {required this.emoji, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 1),
        Text('$value',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}
