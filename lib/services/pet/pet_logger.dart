// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 全应用通用日志系统（从宠物系统扩展为全局日志）
/// 同时输出到 debugPrint + 文件（持久化，应用内任何模块可用）
class PetLogger {
  static final PetLogger _instance = PetLogger._();
  factory PetLogger() => _instance;
  PetLogger._();

  File? _logFile;
  bool _ready = false;
  final _buffer = <String>[];
  static const _maxFileSize = 5 * 1024 * 1024; // 5MB
  static const _logFileName = 'app_debug.log';

  /// 公开日志文件路径（供导出等场景）
  String? get logFilePath => _logFile?.path;

  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/$_logFileName');
      // 超过 5MB 就归档旧日志
      if (await _logFile!.exists()) {
        final size = await _logFile!.length();
        if (size > _maxFileSize) {
          final bak = File('${dir.path}/app_debug.bak.log');
          if (await bak.exists()) await bak.delete();
          await _logFile!.rename(bak.path);
        }
      }
      _ready = true;
      // 刷入积压日志
      for (final entry in _buffer) {
        await _writeToFile(entry);
      }
      _buffer.clear();
      info('Logger', '日志系统就绪，文件=${_logFile!.path}');
    } catch (e) {
      debugPrint('PetLogger.init failed: $e');
    }
  }

  void info(String tag, String msg) => _log('INFO ', tag, msg);
  void warn(String tag, String msg) => _log('WARN ', tag, msg);
  void error(String tag, String msg, [Object? e, StackTrace? st]) {
    final parts = <String>[msg];
    if (e != null) parts.add('| $e');
    if (st != null) parts.add('| $st');
    _log('ERROR', tag, parts.join(' '));
  }
  void trace(String tag, String msg) => _log('TRACE', tag, msg);

  void _log(String level, String tag, String msg) {
    final ts = DateTime.now().toIso8601String();
    final line = '[$level] $ts [$tag] $msg';
    debugPrint(line);
    if (_ready) {
      _writeToFile(line);
    } else {
      _buffer.add(line);
    }
  }

  Future<void> _writeToFile(String line) async {
    try {
      if (_logFile != null) {
        await _logFile!.writeAsString('$line\n', mode: FileMode.append);
      }
    } catch (_) {
      // 写日志失败不能影响主流程
    }
  }

  /// 读取全部日志内容
  Future<String?> getContent() async {
    if (_logFile == null || !await _logFile!.exists()) return null;
    try {
      return await _logFile!.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// 导出为 .txt 到临时目录，返回文件供系统分享使用
  Future<File?> exportTxt() async {
    final content = await getContent();
    if (content == null || content.isEmpty) return null;
    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now();
      final name = 'ai_chat_debug_'
          '${ts.year}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}'
          '_${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}.txt';
      final file = File('${dir.path}/$name');
      await file.writeAsString(content);
      info('Logger', '日志已导出: ${file.path} (${(content.length / 1024).toStringAsFixed(1)} KB)');
      return file;
    } catch (e) {
      error('Logger', '导出失败', e);
      return null;
    }
  }

  /// 导出日志文件路径，供用户分享（兼容旧接口）
  Future<File?> exportLog() async {
    if (_logFile == null || !await _logFile!.exists()) return null;
    return _logFile;
  }

  /// 清空日志
  Future<void> clear() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.delete();
        info('Logger', '日志已清空');
      }
    } catch (_) {}
  }
}
