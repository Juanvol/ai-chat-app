// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/model_config.dart';
import '../services/app/conversation_service.dart';
import '../services/app/persona_service.dart';
import '../services/pet/pet_logger.dart';
import '../utils/page_routes.dart';
import '../screens/persona_screen.dart';

/// 显示搜索弹窗
void showSearchSheet(BuildContext context, ConversationService svc) {
  final cov = svc.currentConversation;
  if (cov == null) return;
  final ctrl = TextEditingController();
  final jumpNotifier = ValueNotifier<int?>(null);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => StatefulBuilder(
        builder: (ctx, setSt) {
          final results = ctrl.text.trim().isEmpty
              ? <({String convId, int msgIndex, String snippet})>[]
              : svc
                  .searchAll(ctrl.text.trim())
                  .where((r) => r.convId == cov.id)
                  .toList();
          return Padding(
            padding: const EdgeInsets.all(C.s16),
            child: Column(children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: C.body(context),
                onChanged: (_) => setSt(() {}),
                decoration: InputDecoration(
                  hintText: '搜索「${cov.title}」的内容...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: ctrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            ctrl.clear();
                            setSt(() {});
                          })
                      : null,
                ),
              ),
              const SizedBox(height: C.s12),
              if (ctrl.text.trim().isNotEmpty)
                Text(results.isEmpty ? '无匹配结果' : '共 ${results.length} 条匹配',
                    style: C.caption(context)),
              const SizedBox(height: C.s8),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  physics: const BouncingScrollPhysics(),
                  itemCount: results.length,
                  itemBuilder: (_, i) {
                    final r = results[i];
                    return ListTile(
                      dense: true,
                      title: Text(r.snippet,
                          style: C.body(context),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.pop(ctx);
                        jumpNotifier.value = r.msgIndex;
                      },
                    );
                  },
                ),
              ),
            ]),
          );
        },
      ),
    ),
  );
}

/// 显示人格切换弹窗
void showPersonaSheet(BuildContext context, PersonaService ps) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(C.r16))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(C.s16),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 32,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: C.s12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFDDDDE5),
                        borderRadius: BorderRadius.circular(2)))),
            Row(children: [
              Text('切换人格', style: C.title(context)),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  pushElastic(context, const PersonaScreen());
                },
                icon: const Icon(Icons.add, size: 14),
                label: const Text('管理', style: TextStyle(fontSize: 12)),
              ),
            ]),
            const SizedBox(height: C.s8),
            if (ps.personas.isEmpty)
              Padding(
                padding: const EdgeInsets.all(C.s16),
                child: Center(
                    child:
                        Text('暂无可用人格', style: C.caption(context))),
              )
            else
              ...ps.personas.map((p) {
                final sel = ps.selected?.id == p.id;
                return ListTile(
                  leading:
                      Text(p.avatar, style: const TextStyle(fontSize: 22)),
                  title: Text(p.name,
                      style: C.body(context).copyWith(
                          fontWeight:
                              sel ? FontWeight.w600 : FontWeight.w400)),
                  subtitle: Text(
                      p.mbti.isNotEmpty
                          ? '${p.mbti} · ${p.traits}'
                          : p.traits,
                      style: C.caption(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: sel
                      ? const Icon(Icons.check_circle,
                          size: 18, color: Color(0xFF7C3AED))
                      : null,
                  onTap: () {
                    ps.selectAndSave(p.id);
                    Navigator.pop(ctx);
                  },
                );
              }),
            const SizedBox(height: C.s12),
          ]),
    ),
  );
}

/// 显示模型选择弹窗
void showModelSheet(BuildContext context, ConversationService svc) {
  if (svc.isLoading) return;
  final providerOrder = [
    'deepseek', 'xiaomi', 'openai', 'siliconflow', 'zhipu', 'moonshot', 'custom'
  ];
  final expandedProviders = <String>{
    providerOrder.firstWhere((p) {
      final cur = ModelConfig.builtIn
          .where((m) => m.id == svc.storage.selModel)
          .firstOrNull;
      return p == cur?.providerId;
    }, orElse: () => 'deepseek')
  };

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(C.r16))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, sc) => ListView(
            controller: sc,
            padding: const EdgeInsets.all(C.s16),
            children: [
              Center(
                  child: Container(
                      width: 32,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: C.s12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFDDDDE5),
                          borderRadius:
                              BorderRadius.circular(2)))),
              Text('选择模型', style: C.title(context)),
              const SizedBox(height: C.s12),
              ...providerOrder.map((pid) {
                final models = ModelConfig.builtIn
                    .where((m) => m.providerId == pid)
                    .toList();
                if (models.isEmpty) return const SizedBox.shrink();
                final provider = ModelConfig.providers
                    .where((p) => p.id == pid)
                    .firstOrNull;
                final isExpanded = expandedProviders.contains(pid);
                final selId = svc.storage.selModel;
                final hasSelected = models.any((m) => m.id == selId);
                return Container(
                  margin: const EdgeInsets.only(bottom: C.s4),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: hasSelected
                            ? const Color(0xFFA78BFA)
                                .withValues(alpha: 0.5)
                            : const Color(0xFFE5E5E5)),
                    borderRadius: BorderRadius.circular(C.r8),
                  ),
                  child: Column(children: [
                    InkWell(
                      onTap: () => setSt(() => isExpanded
                          ? expandedProviders.remove(pid)
                          : expandedProviders.add(pid)),
                      borderRadius: BorderRadius.vertical(
                          top: const Radius.circular(C.r8),
                          bottom: isExpanded
                              ? Radius.zero
                              : const Radius.circular(C.r8)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(children: [
                          if (hasSelected)
                            Container(
                                width: 6,
                                height: 6,
                                margin:
                                    const EdgeInsets.only(right: C.s8),
                                decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFFA78BFA))),
                          Text(provider?.name ?? pid,
                              style: hasSelected
                                  ? C.body(context).copyWith(
                                      fontWeight: FontWeight.w600)
                                  : C.body(context)),
                          const Spacer(),
                          Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 20,
                              color: const Color(0xFF9D9DA8)),
                        ]),
                      ),
                    ),
                    if (isExpanded)
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: RadioGroup<String>(
                          groupValue: selId,
                          onChanged: (v) {
                            if (v == null) return;
                            PetLogger().info(
                                'Home',
                                'model switch: ${svc.storage.selModel} -> $v');
                            svc.setModel(v);
                            Navigator.pop(ctx);
                          },
                          child: Column(
                              children: models
                                  .map((m) => RadioListTile<String>(
                                        value: m.id,
                                        title: Row(children: [
                                          Expanded(
                                              child: Text(m.name,
                                                  style: C.body(
                                                          context)
                                                      .copyWith(
                                                          fontSize:
                                                              15))),
                                          Text(
                                              '¥${m.inputPricePerM.toStringAsFixed(m.inputPricePerM == m.inputPricePerM.roundToDouble() ? 0 : 2)} / ¥${m.outputPricePerM.toStringAsFixed(m.outputPricePerM == m.outputPricePerM.roundToDouble() ? 0 : 2)}',
                                              style: C.caption(
                                                  context)),
                                        ]),
                                        subtitle: Text(m.description,
                                            style: C.caption(context)
                                                .copyWith(
                                                    fontSize: 12)),
                                        dense: true,
                                        visualDensity:
                                            VisualDensity.compact,
                                        contentPadding:
                                            const EdgeInsets.only(
                                                left: 4),
                                      ))
                                  .toList()),
                        ),
                      ),
                  ]),
                );
              }),
            ],
          ),
        );
      },
    ),
  );
}
