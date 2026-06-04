// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../pet/pet_controller.dart';
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

  // ── 阶段/等级映射 ──

  String _stageName(int interactions) {
    if (interactions < 30) return '初识';
    if (interactions < 200) return '熟悉';
    if (interactions < 1000) return '默契';
    return '老友';
  }

  String _levelName(int interactions) {
    if (interactions < 30) return 'Lv.1';
    if (interactions < 200) return 'Lv.2';
    if (interactions < 1000) return 'Lv.3';
    return 'Lv.4';
  }

  // ── 心情 emoji 映射 ──

  String _moodEmoji(double mood) {
    if (mood >= 80) return '😄';
    if (mood >= 50) return '😊';
    if (mood >= 20) return '😐';
    return '😢';
  }

  // ── 展开态内容 ──

  Widget _buildExpandedCard(BuildContext context, PetController ctrl) {
    final interactions = ctrl.state.totalInteractions;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _FunuonuoIcon(size: 56),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '弗糯糯',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 6),
              ColoredBox(
                color: Colors.deepPurple.shade400,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(
                    _levelName(interactions),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${_stageName(interactions)} · ${_moodEmoji(ctrl.state.mood)} 心情${ctrl.state.mood.toInt()}',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatNum(
                emoji: '🍖',
                value: ctrl.state.hunger,
                color: Colors.green,
              ),
              const SizedBox(width: 16),
              _StatNum(
                emoji: '😊',
                value: ctrl.state.mood.toInt(),
                color: Colors.red,
              ),
              const SizedBox(width: 16),
              _StatNum(
                emoji: '⚡',
                value: ctrl.state.energy,
                color: Colors.amber,
              ),
              const SizedBox(width: 16),
              _StatNum(
                emoji: '❤️',
                value: ctrl.state.affection ~/ 10,
                color: Colors.pink,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ActionButtons(ctrl: ctrl),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: NestedScrollView(
        floatHeaderSlivers: true,
        headerSliverBuilder: (context, _) {
          return [
            SliverAppBar(
              pinned: true,
              expandedHeight: 240,
              title: const _CollapsedTitle(),
              flexibleSpace: FlexibleSpaceBar(
                background: Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + kToolbarHeight,
                  ),
                  child: Consumer<PetController>(
                    builder: (context, ctrl, _) =>
                        _buildExpandedCard(context, ctrl),
                  ),
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                child: Container(
                  color: theme.scaffoldBackgroundColor,
                  child: TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: '💬 聊天'),
                      Tab(text: '🧠 记忆'),
                      Tab(text: '📖 日记'),
                      Tab(text: '⚙️ 设置'),
                    ],
                  ),
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: const [
            PetChatScreen(),
            PetMemoryScreen(),
            PetDiaryScreen(),
            PetSettingsScreen(),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────
// _StatNum — 状态数值
// ────────────────────────────────────────

class _StatNum extends StatelessWidget {
  final String emoji;
  final int value;
  final Color color;

  const _StatNum({
    required this.emoji,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 2),
        Text(
          '$value',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────
// _ActionButtons — 操作按钮行
// ────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  final PetController ctrl;

  const _ActionButtons({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ABtn(icon: '🍖', label: '喂食', onTap: () => ctrl.feed()),
        _ABtn(icon: '🎾', label: '玩耍', onTap: () => ctrl.play()),
        _ABtn(icon: '💤', label: '哄睡', onTap: () => ctrl.sleep()),
        _ABtn(icon: '✋', label: '摸摸', onTap: () => ctrl.pet()),
      ],
    );
  }
}

// ────────────────────────────────────────
// _ABtn — 带缩放反馈的操作按钮
// ────────────────────────────────────────

class _ABtn extends StatefulWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;

  const _ABtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ABtn> createState() => _ABtnState();
}

class _ABtnState extends State<_ABtn> {
  double _scale = 1.0;

  void _onTapDown(_) => setState(() => _scale = 0.85);
  void _onTapUp(_) {
    setState(() => _scale = 1.0);
    HapticFeedback.lightImpact();
    widget.onTap();
  }

  void _onTapCancel() => setState(() => _scale = 1.0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedScale(
        scale: _scale,
        curve: Curves.easeOutBack,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 1),
              Text(widget.label, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────
// _CollapsedTitle — 收起态标题行
// ────────────────────────────────────────

class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle();

  @override
  Widget build(BuildContext context) {
    return Consumer<PetController>(
      builder: (context, ctrl, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _FunuonuoIcon(size: 18),
            const SizedBox(width: 4),
            const Text('糯糯', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 10),
            Text(
              '🍖${ctrl.state.hunger}',
              style: const TextStyle(fontSize: 11, color: Colors.green),
            ),
            const SizedBox(width: 4),
            Text(
              '😊${ctrl.state.mood.toInt()}',
              style: const TextStyle(fontSize: 11, color: Colors.red),
            ),
            const SizedBox(width: 4),
            Text(
              '⚡${ctrl.state.energy}',
              style: const TextStyle(fontSize: 11, color: Colors.amber),
            ),
            const SizedBox(width: 4),
            Text(
              '❤️${ctrl.state.affection ~/ 10}',
              style: const TextStyle(fontSize: 11, color: Colors.pink),
            ),
          ],
        );
      },
    );
  }
}

// ────────────────────────────────────────
// _TabBarDelegate — 固定 TabBar
// ────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _TabBarDelegate({required this.child});

  @override
  double get minExtent => 46;

  @override
  double get maxExtent => 46;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => child != oldDelegate.child;
}

// ────────────────────────────────────────
// _FunuonuoIcon — 弗糯糯图标（薄荷绿宠物图标）
// ────────────────────────────────────────

/// 弗糯糯的 Flutter 层图标，用薄荷绿配色匹配角色外观。
/// 真实角色渲染在 Android 原生悬浮窗的帧动画中完成。
class _FunuonuoIcon extends StatelessWidget {
  final double size;
  const _FunuonuoIcon({this.size = 56});

  // 弗糯糯头发薄荷绿（低饱和清新浅青绿）
  static const mintGreen = Color(0xFF8EC8B0);

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.pets, size: size, color: mintGreen);
  }
}
