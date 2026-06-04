// Flutter 3.24 / Dart 3.5
import 'package:flutter/services.dart';

const _agentBridge = MethodChannel('com.example.deepseek_chat/pet_agent_bridge');

/// 弹窗聊天会话元数据
class PopupSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final int msgCount;

  PopupSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.msgCount,
  });

  factory PopupSession.fromMap(Map<String, dynamic> map) {
    return PopupSession(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '新对话',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as num?)?.toInt() ?? 0,
      ),
      msgCount: (map['msgCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 弹窗聊天（原生 SharedPreferences）的会话管理
/// 通过 MethodChannel 与 Kotlin PetForegroundService 通信
class PopupChatService {
  /// 列出所有弹窗会话
  Future<List<PopupSession>> listSessions() async {
    try {
      final raw = await _agentBridge.invokeMethod('listPopupSessions');
      if (raw is List) {
        return raw
            .map((e) => PopupSession.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// 创建新弹窗会话，返回会话 ID
  Future<String?> createSession() async {
    try {
      final id = await _agentBridge.invokeMethod('createPopupSession');
      if (id is String && id.isNotEmpty) return id;
    } catch (_) {}
    return null;
  }

  /// 删除指定会话
  Future<void> deleteSession(String sessionId) async {
    try {
      await _agentBridge.invokeMethod('deletePopupSession', {'sessionId': sessionId});
    } catch (_) {}
  }

  /// 切换当前活跃会话
  Future<void> switchSession(String sessionId) async {
    try {
      await _agentBridge.invokeMethod('switchPopupSession', {'sessionId': sessionId});
    } catch (_) {}
  }

  /// 获取指定会话的消息列表
  Future<List<Map<String, dynamic>>> getSessionMessages(String? sessionId) async {
    try {
      final raw = await _agentBridge.invokeMethod('getPopupSessionMessages', {
        if (sessionId != null) 'sessionId': sessionId,
      });
      if (raw is List) {
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// 获取当前活跃会话的消息（向后兼容 getPopupHistory）
  Future<List<Map<String, dynamic>>> getPopupHistory() async {
    try {
      final raw = await _agentBridge.invokeMethod('getPopupHistory');
      if (raw is List) {
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// 清除弹窗聊天历史（当前会话）
  Future<void> clearPopupHistory() async {
    try {
      await _agentBridge.invokeMethod('clearPopupHistory');
    } catch (_) {}
  }

  /// 保存单条消息到指定弹窗会话（共享到原生 SharedPreferences）
  Future<void> saveMessage(String sessionId, {required bool isUser, required String text}) async {
    try {
      await _agentBridge.invokeMethod('savePopupMessage', {
        'sessionId': sessionId,
        'isUser': isUser,
        'text': text,
      });
    } catch (_) {}
  }

  /// 宠物服务是否正在运行
  Future<bool> isPetRunning() async {
    try {
      final result = await _agentBridge.invokeMethod('isPetRunning');
      return result == true;
    } catch (_) {
      return false;
    }
  }
}
