// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';

class ChatInput extends StatefulWidget {
  final Function(String) onSend;
  final VoidCallback? onStop;
  final bool loading;
  const ChatInput({super.key, required this.onSend, this.onStop, this.loading = false});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _has = false;

  @override
  void initState() { super.initState(); _ctrl.addListener(() { final v = _ctrl.text.trim().isNotEmpty; if (v != _has) setState(() => _has = v); }); }

  void _send() { final t = _ctrl.text.trim(); if (t.isEmpty || widget.loading) return; HapticFeedback.lightImpact(); widget.onSend(t); _ctrl.clear(); _focus.unfocus(); }

  @override
  void dispose() { _ctrl.dispose(); _focus.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(C.s16, C.s16, C.s16, C.s16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(C.r8),
                border: Border.all(
                  color: focused ? cs.primary.withValues(alpha: 0.35) : cs.outline,
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _ctrl, focusNode: _focus, style: C.body(context),
                decoration: InputDecoration(
                  hintText: '输入消息...',
                  hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
                  border: InputBorder.none, filled: false,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                textInputAction: TextInputAction.newline, maxLines: 5, minLines: 1, cursorColor: cs.primary,
              ),
            ),
          ),
          const SizedBox(width: C.s8),
          GestureDetector(
            onTap: widget.loading
                ? widget.onStop
                : (_has ? _send : null),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: widget.loading
                    ? LinearGradient(colors: [Colors.red.shade400, Colors.red.shade700], begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : _has
                        ? LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                        : null,
                color: widget.loading || _has ? null : cs.surfaceContainerHighest,
              ),
              child: Center(
                child: widget.loading
                    ? const Icon(Icons.stop_rounded, size: 18, color: Colors.white)
                    : Icon(Icons.arrow_upward_rounded, size: 20, color: _has ? Colors.white : cs.onSurfaceVariant),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
