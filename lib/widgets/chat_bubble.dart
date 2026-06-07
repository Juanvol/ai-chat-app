// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:markdown/markdown.dart' as md;
import '../config/theme.dart';
import '../models/message.dart';

class ChatBubble extends StatelessWidget {
  final Message msg;
  final VoidCallback? onDislike;
  final VoidCallback? onRegenerate;
  final bool highlighted;
  const ChatBubble({super.key, required this.msg, this.onDislike, this.onRegenerate, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    final mw = MediaQuery.of(context).size.width * 0.85;
    final cs = Theme.of(context).colorScheme;

    String? thinkingText;
    String answerText = msg.content;
    bool thinkingDone = false;
    if (!isUser && msg.content.contains('🤔 思考中...')) {
      final idx = msg.content.indexOf('🤔 思考中...');
      final sep = msg.content.indexOf('\n---', idx);
      if (sep != -1) {
        thinkingText = msg.content.substring(idx, sep).trim();
        answerText = msg.content.substring(sep + 4).trim();
        thinkingDone = true;
      } else {
        thinkingText = msg.content.substring(idx).trim();
        answerText = '';
      }
    }
    if (thinkingText == null && msg.reasoningContent.isNotEmpty) {
      thinkingText = msg.reasoningContent;
      thinkingDone = msg.content.isNotEmpty;
    }

    final isThinking = thinkingText != null && msg.isStreaming && !thinkingDone;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: C.s16, vertical: 7),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(width: 26, height: 26, margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surfaceContainerHighest),
              child: Icon(Icons.auto_awesome, size: 12, color: cs.primary),
            ),
            const SizedBox(width: C.s8),
          ],
          Flexible(
            child: Column(crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
              if (thinkingText != null)
                _DeepThinking(thinking: thinkingText, isThinking: isThinking, mw: mw),
              if (!isThinking && (answerText.isNotEmpty || thinkingText == null))
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  constraints: BoxConstraints(maxWidth: mw),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: highlighted
                        ? cs.primary.withValues(alpha: 0.18)
                        : isUser
                            ? cs.primary.withValues(alpha: 0.1)
                            : cs.surfaceContainerHighest,
                    border: Border.all(
                      color: highlighted ? cs.primary : cs.outline,
                      width: highlighted ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(C.r12), topRight: const Radius.circular(C.r12),
                      bottomLeft: Radius.circular(isUser ? C.r12 : C.s4),
                      bottomRight: Radius.circular(isUser ? C.s4 : C.r12),
                    ),
                  ),
                  child: answerText.isEmpty && msg.isStreaming
                      ? _ThreeDots()
                      : isUser ? SelectableText(answerText, style: C.body(context))
                          : MarkdownBody(data: answerText, selectable: true,
                              builders: {
                                'pre': _CodeBlockBuilder(),
                                'code': _InlineCodeBuilder(),
                              },
                              styleSheet: MarkdownStyleSheet(
                                p: C.body(context),
                                code: TextStyle(color: cs.onSurface, backgroundColor: cs.surface, fontSize: 14),
                                codeblockDecoration: BoxDecoration(color: cs.surface, borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(C.r8), bottomRight: Radius.circular(C.r8),
                                )),
                                blockquoteDecoration: BoxDecoration(
                                  border: Border(left: BorderSide(color: cs.primary.withValues(alpha: 0.6), width: 2))),
                              )),
                ),
              if (!msg.isStreaming)
                Padding(
                  padding: EdgeInsets.only(top: C.s4, left: isUser ? 0 : 4, right: isUser ? 4 : 0),
                  child: Text(msg.createdAt.toLocal().toString().substring(11, 16),
                    style: C.label(context).copyWith(fontSize: 10)),
                ),
              if (!isUser && onDislike != null && !msg.isStreaming)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(
                      onTap: () => Clipboard.setData(ClipboardData(text: answerText)),
                      child: Icon(Icons.copy_outlined, size: 13, color: cs.onSurfaceVariant),
                    ),
                    if (onRegenerate != null) ...[
                      const SizedBox(width: C.s8),
                      GestureDetector(
                        onTap: onRegenerate,
                        child: Icon(Icons.refresh, size: 13, color: cs.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(width: C.s8),
                    GestureDetector(
                      onTap: onDislike,
                      child: Icon(Icons.thumb_down_outlined, size: 13, color: cs.onSurfaceVariant),
                    ),
                  ]),
                ),
              if (isUser && !msg.isStreaming)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4, top: 4),
                    child: GestureDetector(
                      onTap: () => Clipboard.setData(ClipboardData(text: msg.content)),
                      child: const Icon(Icons.copy_outlined, size: 13, color: Color(0xFF8B857D)),
                    ),
                  ),
                ),
            ]),
          ),
          if (isUser) ...[
            const SizedBox(width: C.s8),
            Container(
              width: 26, height: 26, margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surfaceContainerHighest),
              child: Icon(Icons.person, size: 14, color: cs.primary),
            ),
          ],
        ],
      ),
    );
  }
}

// ==================== 深度思考卡片 ====================
class _DeepThinking extends StatefulWidget {
  final String thinking; final bool isThinking; final double mw;
  const _DeepThinking({required this.thinking, required this.isThinking, required this.mw});
  @override
  State<_DeepThinking> createState() => _DeepThinkingState();
}

class _DeepThinkingState extends State<_DeepThinking> with SingleTickerProviderStateMixin {
  final _sc = ScrollController();
  late DateTime _start;
  late final AnimationController _ticker;
  List<String>? _cachedLines;
  bool _open = false;
  bool _scrolling = false;
  double _frozenSecs = 0;
  bool _timerFrozen = false;

  double get _secs => _timerFrozen ? _frozenSecs : DateTime.now().difference(_start).inMilliseconds / 1000;

  @override
  void initState() {
    super.initState();
    _start = DateTime.now();
    _ticker = AnimationController(duration: const Duration(seconds: 60), vsync: this)
      ..addListener(() => setState(() {}));
    if (widget.isThinking) _ticker.repeat();
  }

  @override
  void didUpdateWidget(covariant _DeepThinking old) {
    super.didUpdateWidget(old);
    _cachedLines = null;
    // State 复用：新思考开始时重置计时器
    if (!old.isThinking && widget.isThinking) {
      _start = DateTime.now();
      _timerFrozen = false;
      _frozenSecs = 0;
    }
    if (old.isThinking && !widget.isThinking) {
      _frozenSecs = DateTime.now().difference(_start).inMilliseconds / 1000;
      _timerFrozen = true;
      _ticker.stop();
      setState(() {});
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _open = false);
      });
    }
    if (widget.isThinking && !_ticker.isAnimating) _ticker.repeat();
    if (widget.isThinking && _sc.hasClients && !_scrolling) {
      _scrolling = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrolling = false;
        if (_sc.hasClients) _sc.animateTo(_sc.position.maxScrollExtent, duration: const Duration(milliseconds: 80), curve: Curves.easeOut);
      });
    }
  }

  @override
  void dispose() {
    if (_ticker.isAnimating) {
      _frozenSecs = DateTime.now().difference(_start).inMilliseconds / 1000;
      _timerFrozen = true;
      _ticker.stop();
    }
    _ticker.dispose();
    _sc.dispose();
    super.dispose();
  }

  List<String> get _lines {
    _cachedLines ??= widget.thinking.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return _cachedLines!;
  }

  String get _preview {
    final lines = _lines;
    return lines.length <= 2 ? widget.thinking : lines.sublist(lines.length - 2).join('\n');
  }

  bool get _hasMore => _lines.length > 2;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: C.s8),
      child: GestureDetector(
        onTap: widget.isThinking ? (_hasMore ? () => setState(() => _open = !_open) : null) : () => setState(() => _open = !_open),
        child: Container(
          constraints: BoxConstraints(maxWidth: widget.mw),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(C.r8),
            border: Border.all(color: cs.outline),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: EdgeInsets.fromLTRB(C.s16, C.s12, C.s16, (widget.isThinking || _open) ? C.s8 : C.s12),
              child: Row(children: [
                if (widget.isThinking) ...[
                  const _Bulb(pulse: true),
                  const SizedBox(width: C.s8),
                  Text('思考中${_secs > 0 ? ' （用时${_secs.toStringAsFixed(1)}s）' : ''}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.primary)),
                  if (_hasMore && !_open) ...[
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _open = true),
                      child: Text('展开', style: TextStyle(fontSize: 13, color: cs.primary)),
                    ),
                  ],
                ] else ...[
                  Icon(Icons.lightbulb_outline, size: 14, color: cs.primary),
                  const SizedBox(width: C.s8),
                  Text('已深度思考${_secs > 0 ? ' （用时${_secs.toStringAsFixed(1)}s）' : ''}',
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                  const Spacer(),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 16, color: cs.onSurfaceVariant),
                ],
              ]),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250), curve: Curves.easeInOut,
              child: (widget.isThinking || _open) && widget.thinking.isNotEmpty
                  ? ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: 240, maxWidth: widget.mw - C.s16 * 2),
                      child: SingleChildScrollView(
                        controller: _sc,
                        padding: const EdgeInsets.fromLTRB(C.s16, 0, C.s16, C.s12),
                        child: SizedBox(
                          width: widget.mw - C.s16 * 2,
                          child: Text(widget.isThinking && !_open ? _preview : widget.thinking,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300, color: cs.onSurfaceVariant.withValues(alpha: 0.6), height: 1.6, letterSpacing: 0.15)),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
      ),
    );
  }
}

// ==================== 通用小部件 ====================
class _Bulb extends StatefulWidget {
  final bool pulse;
  const _Bulb({this.pulse = false});
  @override
  State<_Bulb> createState() => _BulbState();
}
class _BulbState extends State<_Bulb> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this);
    if (widget.pulse) _c.repeat(reverse: true);
  }
  @override
  void didUpdateWidget(covariant _Bulb old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.pulse && _c.isAnimating) { _c.stop(); _c.value = 1; }
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Opacity(opacity: 0.5 + _c.value * 0.5, child: child),
      child: Icon(Icons.lightbulb_outline, size: 14, color: cs.primary),
    );
  }
}

class _ThreeDots extends StatefulWidget {
  @override
  State<_ThreeDots> createState() => _ThreeDotsState();
}
class _ThreeDotsState extends State<_ThreeDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() { super.initState(); _c = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this)..repeat(reverse: true); }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, c) => Opacity(opacity: 0.3 + _c.value * 0.4, child: c), child: const Row(mainAxisSize: MainAxisSize.min, children: [_Dot(), SizedBox(width: 8), _Dot(), SizedBox(width: 8), _Dot()]));
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary));
}

// ==================== 代码块 ====================
class _InlineCodeBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent;
    if (!code.contains('\n')) return null;
    if (code.endsWith('\n')) return _CodeBlockWidget(code: code.substring(0, code.length - 1), language: '');
    return _CodeBlockWidget(code: code, language: '');
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    String code = '';
    String language = '';
    if (element.children?.isNotEmpty == true) {
      for (final child in element.children!) {
        if (child is md.Element && child.tag == 'code') {
          if (child.attributes.containsKey('class')) {
            language = child.attributes['class']!.replaceFirst('language-', '');
          }
          code = child.textContent;
          break;
        }
      }
    }
    if (code.isEmpty && element.textContent.isNotEmpty) {
      code = element.textContent;
    }
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    return _CodeBlockWidget(code: code, language: language);
  }
}

class _CodeBlockWidget extends StatelessWidget {
  final String code;
  final String language;
  const _CodeBlockWidget({required this.code, required this.language});

  static const _syntaxTheme = {
    'root':       TextStyle(color: Color(0xFFCDD6F4), backgroundColor: Color(0xFF1E1E2E)),
    'keyword':    TextStyle(color: Color(0xFFCBA6F7), fontStyle: FontStyle.italic),
    'built_in':   TextStyle(color: Color(0xFFCBA6F7)),
    'string':     TextStyle(color: Color(0xFFA6E3A1)),
    'number':     TextStyle(color: Color(0xFFFAB387)),
    'comment':    TextStyle(color: Color(0xFF6C7086), fontStyle: FontStyle.italic),
    'function':   TextStyle(color: Color(0xFF89B4FA)),
    'title':      TextStyle(color: Color(0xFF89B4FA)),
    'class-name': TextStyle(color: Color(0xFFF9E2AF)),
    'type':       TextStyle(color: Color(0xFFF9E2AF)),
    'attr':       TextStyle(color: Color(0xFF89B4FA)),
    'params':     TextStyle(color: Color(0xFFF38BA8)),
    'meta':       TextStyle(color: Color(0xFFCBA6F7)),
    'literal':    TextStyle(color: Color(0xFFFAB387)),
    'section':    TextStyle(color: Color(0xFF89B4FA)),
    'selector':   TextStyle(color: Color(0xFFA6E3A1)),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(C.r8),
        border: Border.all(color: const Color(0xFF313244)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF313244), width: 0.5)),
            ),
            child: Row(children: [
              Text(language.isNotEmpty ? language : 'code',
                style: const TextStyle(fontSize: 11, color: Color(0xFF8B857D), fontFamily: 'monospace')),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('代码已复制'), duration: Duration(seconds: 1)),
                  );
                },
                child: const Icon(Icons.copy_outlined, size: 14, color: Color(0xFF8B857D)),
              ),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: _buildHighlightedCode(),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightedCode() {
    if (code.isEmpty) return const SizedBox.shrink();
    try {
      final result = highlight.parse(code, language: language.isNotEmpty ? language : null);
      final spans = <TextSpan>[];
      for (final node in result.nodes ?? <dynamic>[]) {
        if (node is String) {
          spans.add(TextSpan(text: node));
        } else {
          final className = (node.className as String?) ?? '';
          final style = _syntaxTheme[className] ?? _syntaxTheme['root']!;
          spans.add(TextSpan(text: node.value as String?, style: style));
        }
      }
      return RichText(
        text: TextSpan(
          style: _syntaxTheme['root'],
          children: spans,
        ),
      );
    } catch (_) {
      return SelectableText(code,
        style: _syntaxTheme['root']);
    }
  }
}
