class ChatMessageModel {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final List<String>? suggestions;

  ChatMessageModel({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.suggestions,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final role = json['role']?.toString().toLowerCase();
    return ChatMessageModel(
      id: json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      content: json['content']?.toString() ?? json['message']?.toString() ?? '',
      isUser: role == 'user' || role == 'human',
      timestamp: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ChatConversationModel {
  final String id;
  final String title;
  final DateTime createdAt;

  const ChatConversationModel({
    required this.id,
    required this.title,
    required this.createdAt,
  });

  factory ChatConversationModel.fromJson(Map<String, dynamic> json) {
    return ChatConversationModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Percakapan baru',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
