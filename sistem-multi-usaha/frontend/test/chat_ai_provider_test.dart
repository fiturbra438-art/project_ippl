import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_multi_usaha/providers/chat_ai_provider.dart';

void main() {
  test('busy send blocks navigation and retry reuses optimistic message',
      () async {
    final pending = Completer<Map<String, dynamic>?>();
    var calls = 0;
    final provider = ChatAiProvider(
      get: (_) async => {'status': 'error'},
      post: (_, body, {timeout = const Duration(seconds: 15)}) {
        expect(timeout, const Duration(seconds: 40));
        expect(body, {'message': 'Hello'});
        calls++;
        return calls == 1
            ? pending.future
            : Future.value({
                'reply': 'Hi',
                'conversation_id': '1',
                'remaining_quota': 5,
              });
      },
    );
    final send = provider.sendMessage('Hello');
    provider.startNewConversation();
    await provider.loadMessages('other');
    await provider.loadConversations();
    await provider.sendMessage('Ignored');
    expect(provider.messages.length, 1);
    expect(provider.isBusy, isTrue);
    pending.complete({'status': 'error'});
    await send;
    expect(provider.canRetry, isTrue);
    await provider.retry();
    expect(provider.messages.length, 2);
    expect(provider.conversationId, '1');
    expect(provider.sisaKuotaAi, 5);
    expect(provider.error, isNotNull);
    expect(provider.canRetry, isFalse);
    await provider.retry();
    expect(calls, 2);
  });

  test('history selection commits only after success and clears stale messages',
      () async {
    final pending = Completer<Map<String, dynamic>?>();
    var calls = 0;
    final provider = ChatAiProvider(get: (_) {
      calls++;
      return calls == 1
          ? Future.value({
              'messages': [
                {'id': '1', 'role': 'user', 'content': 'Old'},
              ]
            })
          : pending.future;
    });
    await provider.loadMessages('old');
    expect(provider.conversationId, 'old');
    final load = provider.loadMessages('new');
    expect(provider.conversationId, isNull);
    expect(provider.messages, isEmpty);
    provider.startNewConversation();
    await provider.loadMessages('ignored');
    await provider.sendMessage('ignored');
    expect(calls, 2);
    pending.complete({'status': 'error'});
    await load;
    expect(provider.conversationId, isNull);
    expect(provider.canRetry, isFalse);
    expect(provider.isBusy, isFalse);
  });
}
