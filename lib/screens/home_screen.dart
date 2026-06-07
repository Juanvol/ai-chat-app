// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/model_config.dart';
import '../services/app/conversation_service.dart';
import '../services/app/memory_service.dart';
import '../services/app/persona_service.dart';
import '../services/app/feedback_service.dart';
import '../widgets/home_welcome.dart';
import '../widgets/home_drawer.dart';
import '../widgets/home_sheets.dart';
import '../widgets/home_chat_view.dart';
import 'feedback_screen.dart';
import '../utils/page_routes.dart' show pushElastic;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationService>(
      builder: (context, svc, _) {
        return Scaffold(
          appBar: AppBar(
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu, size: 22),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            title: GestureDetector(
              onTap: svc.currentConversation != null
                  ? () => showModelSheet(context, svc)
                  : null,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(svc.currentConversation?.title ?? '',
                      style: C.title(context)),
                  if (svc.currentConversation != null)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_currentModelName(svc), style: C.label(context)),
                      const Icon(Icons.arrow_drop_down,
                          size: 18, color: Color(0xFFA0A0AB)),
                    ]),
                ],
              ),
            ),
            actions: [
              if (svc.currentConversation != null) ...[
                IconButton(
                  icon: const Icon(Icons.search, size: 20),
                  tooltip: '搜索对话内容',
                  onPressed: () => showSearchSheet(context, svc),
                ),
                const SizedBox(width: 0),
                Consumer<FeedbackService>(
                  builder: (_, fb, __) {
                    final active = fb.adjustmentText.isNotEmpty;
                    return IconButton(
                      icon: Stack(children: [
                        Icon(Icons.auto_awesome,
                            size: 18,
                            color: active
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF888891)),
                        if (fb.hasNewAdjustment)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                          ),
                      ]),
                      tooltip: active ? 'AI 已根据你的反馈进化' : '反馈',
                      onPressed: () =>
                          pushElastic(context, const FeedbackScreen()),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.add_comment_outlined, size: 20),
                  onPressed: svc.createConversation,
                ),
              ],
            ],
          ),
          drawer: HomeDrawer(svc: svc),
          body: AnimatedSwitcher(
            duration: 300.ms,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: svc.currentConversation == null
                ? HomeWelcome(
                    key: const ValueKey('welcome'),
                    onTap: (q) {
                      svc.createConversation();
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => svc.sendMessage(q));
                    },
                  )
                : HomeChatView(
                    key: ValueKey('chat_${svc.currentConversation!.id}'),
                    conversation: svc.currentConversation!,
                    loading: svc.isLoading,
                    onSend: (t) {
                      final memSvc = context.read<MemoryService>();
                      final perSvc = context.read<PersonaService>();
                      final fbSvc = context.read<FeedbackService>();
                      svc.sendMessage(t,
                        memoryText: memSvc.promptText,
                        personaPrompt: perSvc.selected?.fullPrompt,
                        adjustmentText: fbSvc.adjustmentText,
                        modelId: svc.storage.selModel,
                        maxTokens: svc.globalMaxTokens,
                      );
                    },
                    onStop: () {
                      svc.stopGeneration();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('已停止生成'),
                            duration: Duration(seconds: 1)),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

String _currentModelName(ConversationService svc) {
  final id = svc.storage.selModel;
  return ModelConfig.builtIn.where((m) => m.id == id).firstOrNull?.name ?? id;
}
