// Flutter 3.24 / Dart 3.5
import '../models/suggestion.dart';

/// 用户对建议的反馈
enum UserFeedbackType { ignore, click, dismiss, swipeLeft, swipeRight }

class UserFeedback {
  final String suggestionId;
  final UserFeedbackType type;
  final DateTime timestamp;

  UserFeedback({
    required this.suggestionId,
    required this.type,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// 输出驱动接口：气泡/聊天/通知/语音都实现这个
abstract class IOutputDriver {
  String get id;
  bool canHandle(SuggestionLevel level);
  Future<void> deliver(Suggestion suggestion);
  Stream<UserFeedback> get feedback;
}
