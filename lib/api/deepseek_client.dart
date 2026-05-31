import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/message.dart';

class StreamChunk {
  final String text;
  final bool isThinking;
  final Map<String, int>? usage;
  const StreamChunk(this.text, {this.isThinking = false, this.usage});
}

class DeepSeekException implements Exception {
  final String message;
  final int? statusCode;
  DeepSeekException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class LLMClient {
  final Dio _dio;
  String? _apiKey;
  String _systemPrompt = '';

  LLMClient({String? apiKey})
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 5),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
        )) {
    _apiKey = apiKey;
    _updateAuth();
    _dio.interceptors.add(_ErrorInterceptor());
  }

  void setApiKey(String key) { _apiKey = key; _updateAuth(); }
  void setSystemPrompt(String p) => _systemPrompt = p;
  String? get apiKey => _apiKey;
  String get systemPrompt => _systemPrompt;
  void _updateAuth() {
    if (_apiKey != null && _apiKey!.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $_apiKey';
    }
  }

  void _addThinking(Map<String, dynamic> body, bool enabled, String effort, String providerId) {
    if (providerId == 'xiaomi') {
      body['chat_template_kwargs'] = {'enable_thinking': enabled};
    } else {
      body['thinking'] = {'type': enabled ? 'enabled' : 'disabled'};
      if (enabled) body['reasoning_effort'] = effort;
    }
  }

  /// 流式请求
  Stream<StreamChunk> sendStream({
    required List<Message> history,
    required String userContent,
    String baseUrl = 'https://api.deepseek.com',
    String? apiKey,
    String model = 'deepseek-v4-pro',
    int maxTokens = 8192,
    bool thinkingEnabled = true,
    String reasoningEffort = 'high',
    String providerId = 'deepseek',
    CancelToken? cancelToken,
  }) async* {
    final originalKey = _apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      _apiKey = apiKey;
      _updateAuth();
    }

    final messages = _buildMessages(history, userContent);
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'max_tokens': maxTokens,
      'stream': true,
    };
    _addThinking(body, thinkingEnabled, reasoningEffort, providerId);

    try {
      final response = await _dio.post(
        '$baseUrl/v1/chat/completions',
        data: body,
        options: Options(responseType: ResponseType.stream),
        cancelToken: cancelToken,
      );

      final stream = response.data.stream as Stream<List<int>>;
      String buffer = '';

      await for (final bytes in stream) {
        if (cancelToken?.isCancelled == true) return;
        buffer += utf8.decode(bytes, allowMalformed: true);
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          if (data == '[DONE]') return;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices == null || choices.isEmpty) continue;
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            if (delta == null) continue;
            final reasoning = delta['reasoning_content'] as String?;
            final content = delta['content'] as String?;
            if (reasoning != null && reasoning.isNotEmpty) {
              yield StreamChunk(reasoning, isThinking: true);
            }
            if (content != null && content.isNotEmpty) {
              yield StreamChunk(content);
            }
            final usageJson = json['usage'] as Map<String, dynamic>?;
            if (usageJson != null) {
              yield StreamChunk('', usage: {
                'prompt_tokens': (usageJson['prompt_tokens'] as num).toInt(),
                'completion_tokens': (usageJson['completion_tokens'] as num).toInt(),
                'total_tokens': (usageJson['total_tokens'] as num).toInt(),
              });
            }
          } catch (_) {}
        }
      }
    } finally {
      if (originalKey != apiKey) {
        _apiKey = originalKey;
        _updateAuth();
      }
    }
  }

  /// 非流式请求
  Future<({String content, String reasoning, Map<String, int>? usage})> send({
    required List<Message> history,
    required String userContent,
    String baseUrl = 'https://api.deepseek.com',
    String? apiKey,
    String model = 'deepseek-v4-pro',
    int maxTokens = 8192,
    bool thinkingEnabled = false,
    String reasoningEffort = 'high',
    String providerId = 'deepseek',
  }) async {
    final originalKey = _apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      _apiKey = apiKey;
      _updateAuth();
    }
    final body = <String, dynamic>{
      'model': model, 'messages': _buildMessages(history, userContent),
      'max_tokens': maxTokens, 'stream': false,
    };
    _addThinking(body, thinkingEnabled, reasoningEffort, providerId);

    try {
      final response = await _dio.post('$baseUrl/v1/chat/completions', data: body);
      final msg = response.data['choices']?[0]?['message'];
      final usageJson = response.data['usage'] as Map<String, dynamic>?;
      return (
        content: msg?['content'] as String? ?? '',
        reasoning: msg?['reasoning_content'] as String? ?? '',
        usage: usageJson != null ? {
          'prompt_tokens': (usageJson['prompt_tokens'] as num).toInt(),
          'completion_tokens': (usageJson['completion_tokens'] as num).toInt(),
          'total_tokens': (usageJson['total_tokens'] as num).toInt(),
        } : null,
      );
    } finally {
      if (originalKey != apiKey) { _apiKey = originalKey; _updateAuth(); }
    }
  }

  /// 视觉请求（非流式），用于截图分析等场景
  /// [base64Image] 纯 base64 字符串（不含 data: URI 前缀）
  Future<String> sendVision({
    required String base64Image,
    String mimeType = 'image/png',
    required String prompt,
    String baseUrl = 'https://token-plan-cn.xiaomimimo.com',
    String? apiKey,
    String model = 'mimo-v2-omni',
    int maxTokens = 1024,
  }) async {
    final originalKey = _apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      _apiKey = apiKey;
      _updateAuth();
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:$mimeType;base64,$base64Image',
              },
            },
            {'type': 'text', 'text': prompt},
          ],
        },
      ],
      'max_tokens': maxTokens,
      'stream': false,
    };

    try {
      final response = await _dio.post('$baseUrl/v1/chat/completions', data: body);
      final content = response.data['choices']?[0]?['message']?['content'] as String?;
      // MiMo 有时在 reasoning_content 中返回思考内容
      final reasoning = response.data['choices']?[0]?['message']?['reasoning_content'] as String?;
      return content ?? reasoning ?? '';
    } finally {
      if (originalKey != apiKey) {
        _apiKey = originalKey;
        _updateAuth();
      }
    }
  }

  List<Map<String, String>> _buildMessages(List<Message> history, String userContent) {
    final msgs = <Map<String, String>>[];
    if (_systemPrompt.isNotEmpty) msgs.add({'role': 'system', 'content': _systemPrompt});
    for (final m in history) {
      if (!m.isStreaming) msgs.add({'role': m.role, 'content': m.content});
    }
    msgs.add({'role': 'user', 'content': userContent});
    return msgs;
  }
}

class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    String msg;
    switch (err.type) {
      case DioExceptionType.connectionTimeout: msg = '连接超时'; break;
      case DioExceptionType.receiveTimeout: msg = '响应超时'; break;
      case DioExceptionType.badResponse:
        final code = err.response?.statusCode;
        if (code == 401) msg = 'API Key 无效';
        else if (code == 402) msg = '余额不足';
        else if (code == 429) msg = '请求太频繁';
        else msg = '服务器错误 ($code)';
        break;
      default: msg = '网络错误'; break;
    }
    handler.reject(DioException(requestOptions: err.requestOptions, response: err.response,
      type: err.type, message: msg, error: err.error));
  }
}
