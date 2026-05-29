// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/models/message.dart';
import 'package:deepseek_chat/models/conversation.dart';
import 'package:deepseek_chat/models/model_config.dart';
import 'package:deepseek_chat/models/feedback_entry.dart';
import 'package:deepseek_chat/models/memory.dart';
import 'package:deepseek_chat/models/persona.dart';
import 'package:deepseek_chat/models/token_usage.dart';

void main() {
  group('Message', () {
    test('toJson then fromJson roundtrip', () {
      final now = DateTime.now();
      final msg = Message(
        id: 'msg-1', role: 'user', content: 'Hello',
        reasoningContent: 'thinking...', createdAt: now, isStreaming: false,
      );
      final json = msg.toJson();
      final restored = Message.fromJson(json);
      expect(restored.id, 'msg-1');
      expect(restored.role, 'user');
      expect(restored.content, 'Hello');
      expect(restored.reasoningContent, 'thinking...');
      expect(restored.isStreaming, false);
    });

    test('defaults', () {
      final msg = Message(id: '1', role: 'assistant', content: '', createdAt: DateTime.now());
      expect(msg.reasoningContent, '');
      expect(msg.isStreaming, false);
    });

    test('copyWith preserves unchanged fields', () {
      final msg = Message(id: '1', role: 'assistant', content: 'old',
          reasoningContent: 'think', createdAt: DateTime.now(), isStreaming: true);
      final updated = msg.copyWith(content: 'new', isStreaming: false);
      expect(updated.content, 'new');
      expect(updated.isStreaming, false);
      expect(updated.id, '1');
      expect(updated.reasoningContent, 'think');
      expect(updated.role, 'assistant');
    });

    test('toJson includes all fields', () {
      final now = DateTime.now();
      final msg = Message(id: 'x', role: 'user', content: 'c',
          reasoningContent: 'r', createdAt: now, isStreaming: true);
      final j = msg.toJson();
      expect(j['id'], 'x');
      expect(j['role'], 'user');
      expect(j['content'], 'c');
      expect(j['reasoningContent'], 'r');
      expect(j['isStreaming'], true);
      expect(j['createdAt'], now.toIso8601String());
    });
  });

  group('Conversation', () {
    test('toJson then fromJson roundtrip', () {
      final now = DateTime.now();
      final conv = Conversation(
        id: 'conv-1', title: 'Test', createdAt: now, updatedAt: now,
        modelId: 'deepseek-chat',
        messages: [
          Message(id: 'm1', role: 'user', content: 'Hi', createdAt: now),
          Message(id: 'm2', role: 'assistant', content: 'Hello!', createdAt: now),
        ],
      );
      final json = conv.toJson();
      final restored = Conversation.fromJson(json);
      expect(restored.id, 'conv-1');
      expect(restored.title, 'Test');
      expect(restored.modelId, 'deepseek-chat');
      expect(restored.messages.length, 2);
      expect(restored.messages[0].content, 'Hi');
      expect(restored.messages[1].content, 'Hello!');
    });

    test('messageCount excludes streaming messages', () {
      final conv = Conversation(id: 'c1', title: 'Test',
        createdAt: DateTime.now(), updatedAt: DateTime.now(), messages: [
          Message(id: 'm1', role: 'user', content: 'Hi', createdAt: DateTime.now()),
          Message(id: 'm2', role: 'assistant', content: '', createdAt: DateTime.now(), isStreaming: true),
        ],
      );
      expect(conv.messageCount, 1);
    });

    test('messageCount 0 for empty messages', () {
      final conv = Conversation(id: 'c2', title: 'Empty',
        createdAt: DateTime.now(), updatedAt: DateTime.now(), messages: [],
      );
      expect(conv.messageCount, 0);
    });

    test('default modelId is deepseek-chat', () {
      final conv = Conversation(id: 'c3', title: 'T',
        createdAt: DateTime.now(), updatedAt: DateTime.now(), messages: [],
      );
      expect(conv.modelId, 'deepseek-chat');
    });

    test('title is mutable', () {
      final conv = Conversation(id: 'c4', title: 'Old',
        createdAt: DateTime.now(), updatedAt: DateTime.now(), messages: [],
      );
      conv.title = 'New';
      expect(conv.title, 'New');
    });
  });

  group('ModelConfig', () {
    test('builtIn list is non-empty', () {
      expect(ModelConfig.builtIn.isNotEmpty, true);
    });

    test('providers list is non-empty', () {
      expect(ModelConfig.providers.isNotEmpty, true);
    });

    test('builtIn model ids are unique', () {
      final ids = ModelConfig.builtIn.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every builtIn model references a valid provider', () {
      final providerIds = ModelConfig.providers.map((p) => p.id).toSet();
      for (final m in ModelConfig.builtIn) {
        expect(providerIds.contains(m.providerId), true,
            reason: '${m.id} references unknown provider ${m.providerId}');
      }
    });
  });

  group('FeedbackEntry', () {
    test('toJson then fromJson roundtrip', () {
      final now = DateTime.now();
      final fb = FeedbackEntry(
        id: 'fb-1', conversationId: 'conv-1',
        userMessage: '你好', aiResponse: '你好！有什么可以帮你的？',
        reason: '不准确', createdAt: now, processed: true,
        adjustmentResult: '需要更精确',
      );
      final j = fb.toJson();
      final r = FeedbackEntry.fromJson(j);
      expect(r.id, 'fb-1');
      expect(r.conversationId, 'conv-1');
      expect(r.userMessage, '你好');
      expect(r.aiResponse, '你好！有什么可以帮你的？');
      expect(r.reason, '不准确');
      expect(r.processed, true);
      expect(r.adjustmentResult, '需要更精确');
    });

    test('defaults: processed=false, reason=不满意', () {
      final fb = FeedbackEntry(id: 'fb-2', conversationId: 'c1',
        userMessage: 'hi', aiResponse: 'hello', createdAt: DateTime.now(),
      );
      expect(fb.processed, false);
      expect(fb.reason, '不满意');
      expect(fb.adjustmentResult, isNull);
    });

    test('reason is mutable', () {
      final fb = FeedbackEntry(id: 'fb-3', conversationId: 'c1',
        userMessage: 'hi', aiResponse: 'hello', createdAt: DateTime.now(),
      );
      fb.reason = '跑题';
      expect(fb.reason, '跑题');
    });
  });

  group('Memory', () {
    test('toJson then fromJson roundtrip', () {
      final now = DateTime.now();
      final m = Memory(id: 'mem-1', content: '用户喜欢Python',
        importance: 4, createdAt: now, updatedAt: now, tags: ['python', 'coding'],
      );
      final j = m.toJson();
      final r = Memory.fromJson(j);
      expect(r.id, 'mem-1');
      expect(r.content, '用户喜欢Python');
      expect(r.importance, 4);
      expect(r.tags, ['python', 'coding']);
    });

    test('defaults: importance=3, tags=[]', () {
      final now = DateTime.now();
      final m = Memory(id: 'mem-2', content: 'test', createdAt: now, updatedAt: now);
      expect(m.importance, 3);
      expect(m.tags, []);
    });

    test('content is mutable', () {
      final now = DateTime.now();
      final m = Memory(id: 'mem-3', content: 'old', createdAt: now, updatedAt: now);
      m.content = 'new';
      expect(m.content, 'new');
    });

    test('fromJson handles missing tags', () {
      final now = DateTime.now();
      final j = {'id': 'mem-4', 'content': 'test', 'importance': 2,
        'createdAt': now.toIso8601String(), 'updatedAt': now.toIso8601String()};
      final m = Memory.fromJson(j);
      expect(m.tags, []);
    });
  });

  group('Persona', () {
    test('toJson then fromJson roundtrip', () {
      final now = DateTime.now();
      final p = Persona(id: 'p-1', name: '码农', avatar: '💻',
        systemPrompt: '你是一个程序员', temperature: 0.5, modelId: 'ds-chat',
        createdAt: now, updatedAt: now,
        replyLength: 'brief', tone: 'casual', language: 'zh', expertise: 'coding',
        mbti: 'INTP', traits: '逻辑清晰',
      );
      final j = p.toJson();
      final r = Persona.fromJson(j);
      expect(r.id, 'p-1');
      expect(r.name, '码农');
      expect(r.avatar, '💻');
      expect(r.systemPrompt, '你是一个程序员');
      expect(r.temperature, 0.5);
      expect(r.modelId, 'ds-chat');
      expect(r.replyLength, 'brief');
      expect(r.tone, 'casual');
      expect(r.language, 'zh');
      expect(r.expertise, 'coding');
      expect(r.mbti, 'INTP');
      expect(r.traits, '逻辑清晰');
    });

    test('defaults', () {
      final now = DateTime.now();
      final p = Persona(id: 'p-2', name: 'Test', systemPrompt: 'SP',
        createdAt: now, updatedAt: now,
      );
      expect(p.avatar, '🤖');
      expect(p.temperature, 0.7);
      expect(p.modelId, 'deepseek-chat');
      expect(p.replyLength, 'normal');
      expect(p.tone, 'professional');
      expect(p.language, 'zh');
      expect(p.expertise, 'general');
      expect(p.mbti, '');
      expect(p.traits, '');
      expect(p.customExpertise, '');
    });

    test('copyWith partial update', () {
      final now = DateTime.now();
      final p = Persona(id: 'p-3', name: '原', systemPrompt: 'SP',
        createdAt: now, updatedAt: now, mbti: 'INTJ', traits: '冷静',
      );
      final updated = p.copyWith(name: '新', traits: '热情');
      expect(updated.name, '新');
      expect(updated.traits, '热情');
      expect(updated.mbti, 'INTJ');
      expect(updated.id, 'p-3');
      // copyWith 内 new DateTime.now() 可能与 now 同毫秒
      expect(updated.updatedAt.millisecondsSinceEpoch >= now.millisecondsSinceEpoch, true);
    });

    test('defaultPersona creates valid persona', () {
      final p = Persona.defaultPersona('default');
      expect(p.id, 'default');
      expect(p.name, '默认助手');
      expect(p.systemPrompt.isNotEmpty, true);
    });

    test('fullPrompt includes all set instructions', () {
      final now = DateTime.now();
      final p = Persona(id: 'p-4', name: 'X', systemPrompt: 'BASE',
        createdAt: now, updatedAt: now,
        mbti: 'INTP', traits: '好奇心强',
        replyLength: 'brief', tone: 'casual', language: 'zh', expertise: 'coding',
      );
      final fp = p.fullPrompt;
      expect(fp.contains('BASE'), true);
      expect(fp.contains('INTP'), true);
      expect(fp.contains('好奇心强'), true);
    });

    test('fullPrompt excludes empty instructions', () {
      final now = DateTime.now();
      final p = Persona(id: 'p-5', name: 'X', systemPrompt: 'BASE',
        createdAt: now, updatedAt: now,
        mbti: '', traits: '', replyLength: 'normal', tone: 'formal',
        language: 'mixed', expertise: 'general',
      );
      final fp = p.fullPrompt;
      // tone=formal → '', language=mixed → '', replyLength=normal → ''
      // expertise=general → '' — 全部返回空，仅剩 systemPrompt
      expect(fp, 'BASE');
    });
  });

  group('TokenUsage', () {
    test('toJson then fromJson roundtrip', () {
      final now = DateTime.now();
      final u = TokenUsage(id: 'u-1', conversationId: 'c1',
        modelId: 'ds-v4-pro', providerId: 'deepseek',
        promptTokens: 100, completionTokens: 200, createdAt: now,
      );
      final j = u.toJson();
      final r = TokenUsage.fromJson(j);
      expect(r.id, 'u-1');
      expect(r.conversationId, 'c1');
      expect(r.modelId, 'ds-v4-pro');
      expect(r.providerId, 'deepseek');
      expect(r.promptTokens, 100);
      expect(r.completionTokens, 200);
      expect(r.totalTokens, 300);
    });

    test('totalTokens sum', () {
      final u = TokenUsage(id: 'u-2', conversationId: 'c1',
        modelId: 'm', providerId: 'p',
        promptTokens: 0, completionTokens: 0, createdAt: DateTime.now(),
      );
      expect(u.totalTokens, 0);
    });
  });

  group('ModelConfig pricing', () {
    test('all builtIn models have non-negative prices', () {
      for (final m in ModelConfig.builtIn) {
        expect(m.inputPricePerM, isNonNegative, reason: '${m.id} input price negative');
        expect(m.outputPricePerM, isNonNegative, reason: '${m.id} output price negative');
        expect(m.currency, isIn(['USD', 'CNY']), reason: '${m.id} unknown currency');
      }
    });
  });
}
