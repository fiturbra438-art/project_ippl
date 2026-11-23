import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_multi_usaha/models/chat_model.dart';

void main() {
  test('parses conversation and message contract', () {
    final conversation = ChatConversationModel.fromJson({
      'id': 'conversation-1',
      'title': 'Penjualan',
      'created_at': '2026-01-01T10:00:00Z',
    });
    final message = ChatMessageModel.fromJson({
      'id': 'message-1',
      'role': 'assistant',
      'content': 'Ringkasan penjualan',
      'created_at': '2026-01-01T10:01:00Z',
    });

    expect(conversation.id, 'conversation-1');
    expect(conversation.title, 'Penjualan');
    expect(message.id, 'message-1');
    expect(message.content, 'Ringkasan penjualan');
    expect(message.isUser, isFalse);
  });

  test('parses legacy message content', () {
    final message = ChatMessageModel.fromJson({
      'id': 1,
      'message': 'Jawaban lama',
      'role': 'user',
    });

    expect(message.content, 'Jawaban lama');
    expect(message.isUser, isTrue);
  });
}
