// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../services/pet/pet_token_service.dart';

class PetInfoChips extends StatefulWidget {
  const PetInfoChips({super.key});

  @override
  State<PetInfoChips> createState() => _PetInfoChipsState();
}

class _PetInfoChipsState extends State<PetInfoChips> {
  int _today = 0;
  int _budget = 50000;
  int _remaining = 50000;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final svc = context.read<PetTokenService>();
    final usage = await svc.getTodayUsage();
    final remaining = await svc.getBudgetRemaining();
    if (!mounted) return;
    setState(() {
      _today = usage.totalTokens;
      _budget = svc.dailyBudget ?? 50000;
      _remaining = remaining;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          _Chip(label: '💰 $_today / ${(_budget / 1000).round()}k Token')
              .animate()
              .slideY(begin: 0.3, end: 0, delay: 600.ms, duration: 400.ms, curve: Curves.easeOut)
              .fadeIn(delay: 600.ms, duration: 300.ms),
          _Chip(label: '剩余 ${(_remaining / 1000).round()}k')
              .animate()
              .slideY(begin: 0.3, end: 0, delay: 700.ms, duration: 400.ms, curve: Curves.easeOut)
              .fadeIn(delay: 700.ms, duration: 300.ms),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}
