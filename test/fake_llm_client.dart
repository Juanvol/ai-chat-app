// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:deepseek_chat/api/deepseek_client.dart';
import 'package:deepseek_chat/models/message.dart';

class FakeLLMClient extends LLMClient {
  final List<StreamChunk> _chunks;
  final bool _throwImmediately;
  final bool _throwAfterChunks;

  CancelToken? _capturedCancelToken;
  CancelToken? get capturedCancelToken => _capturedCancelToken;

  FakeLLMClient({
    List<StreamChunk>? chunks,
    bool throwImmediately = false,
    bool throwAfterChunks = false,
    super.apiKey,
  })  : _chunks = chunks ?? [],
        _throwImmediately = throwImmediately,
        _throwAfterChunks = throwAfterChunks;

  factory FakeLLMClient.text(String text) =>
      FakeLLMClient(chunks: [StreamChunk(text)], apiKey: 'x');
  factory FakeLLMClient.empty() => FakeLLMClient(apiKey: 'x');
  factory FakeLLMClient.fromTexts(List<String> texts) =>
      FakeLLMClient(chunks: texts.map((t) => StreamChunk(t)).toList(), apiKey: 'x');
  factory FakeLLMClient.noKey() => FakeLLMClient(apiKey: '');
  factory FakeLLMClient.error() =>
      FakeLLMClient(apiKey: 'x', throwImmediately: true);
  factory FakeLLMClient.errorAfterChunks(List<StreamChunk> chunks) =>
      FakeLLMClient(chunks: chunks, throwAfterChunks: true, apiKey: 'x');

  @override
  Stream<StreamChunk> sendStream({
    required List<Message> history,
    required String userContent,
    String baseUrl = 'https://api.deepseek.com',
    String chatPath = '/v1/chat/completions',
    String? apiKey,
    String model = 'deepseek-v4-pro',
    int maxTokens = 8192,
    bool thinkingEnabled = true,
    String reasoningEffort = 'high',
    String providerId = 'deepseek',
    CancelToken? cancelToken,
  }) async* {
    _capturedCancelToken = cancelToken;

    if (_throwImmediately) {
      yield* _errorStream();
      return;
    }

    for (final c in _chunks) {
      if (cancelToken?.isCancelled == true) return;
      yield c;
      await Future.delayed(Duration.zero);
    }

    if (_throwAfterChunks) {
      yield* _errorStream();
    }
  }

  @override
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
    if (_throwImmediately) {
      throw DioException(requestOptions: RequestOptions(path: ''), type: DioExceptionType.connectionError);
    }
    final text = _chunks.map((c) => c.text).join();
    return (content: text, reasoning: '', usage: null);
  }

  Stream<StreamChunk> _errorStream() async* {
    throw DioException(
      requestOptions: RequestOptions(path: ''),
      type: DioExceptionType.connectionError,
      message: 'Fake error',
    );
  }
}
