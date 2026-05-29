// Flutter 3.24 / Dart 3.5
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/conversation.dart';

Future<String> exportConversation(Conversation c, {bool asJson = false}) async {
  final dir = await getApplicationDocumentsDirectory();
  final ext = asJson ? 'json' : 'md';
  final date = c.createdAt.toLocal().toString().substring(0, 10);
  final filename = '${_safeName(c.title)}_$date.$ext';
  final file = File('${dir.path}/exports/$filename');
  await file.parent.create(recursive: true);

  if (asJson) {
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(c.toJson()));
  } else {
    final buf = StringBuffer();
    buf.writeln('# ${c.title}');
    buf.writeln();
    buf.writeln('> ${c.createdAt.toLocal().toString().substring(0, 19)}  |  共 ${c.messageCount} 条消息');
    buf.writeln();
    for (final m in c.messages) {
      if (m.isStreaming) continue;
      final role = m.role == 'user' ? '**你**' : '**AI**';
      buf.writeln('---');
      buf.writeln('### $role');
      buf.writeln();
      buf.writeln(m.content);
      buf.writeln();
    }
    await file.writeAsString(buf.toString());
  }

  return file.path;
}

String _safeName(String title) {
  return title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').substring(0, title.length.clamp(0, 40));
}
