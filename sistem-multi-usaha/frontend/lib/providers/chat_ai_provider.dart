import 'package:flutter/material.dart';
import '../models/chat_model.dart';
import '../services/api_service.dart';

class ChatAiProvider extends ChangeNotifier {
  ChatAiProvider({
    Future<Map<String, dynamic>?> Function(String)? get,
    Future<Map<String, dynamic>?> Function(String, Map<String, dynamic>,
            {Duration timeout})?
        post,
  })  : _get = get ?? ApiService.get,
        _post = post ?? ApiService.post;

  final Future<Map<String, dynamic>?> Function(String) _get;
  final Future<Map<String, dynamic>?> Function(String, Map<String, dynamic>,
      {Duration timeout}) _post;
  final List<ChatMessageModel> _messages = [];
  final List<ChatConversationModel> _conversations = [];
  String? _conversationId;
  bool _isLoading = false;
  bool _isTyping = false;
  int? _sisaKuotaAi;
  String? _error;
  String? _failedMessage;

  List<ChatMessageModel> get messages => List.unmodifiable(_messages);
  List<ChatConversationModel> get conversations =>
      List.unmodifiable(_conversations);
  String? get conversationId => _conversationId;
  bool get isLoading => _isLoading;
  bool get isTyping => _isTyping;
  bool get isBusy => _isLoading || _isTyping;
  bool get canRetry => _failedMessage != null && !isBusy;
  int? get sisaKuotaAi => _sisaKuotaAi;
  String? get error => _error;

  Future<void> loadConversations() async {
    if (isBusy) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    await _fetchConversations();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _fetchConversations() async {
    try {
      final response = await _get('/ai/conversations');
      final items = _payload(response)['conversations'];
      if (_isError(response) || items is! List) {
        _error = _errorMessage(response);
        return;
      }
      final conversations = items
          .map((item) =>
              ChatConversationModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      _conversations
        ..clear()
        ..addAll(conversations);
    } catch (e) {
      _error = e.toString();
    }
  }

  Future<void> loadMessages(String id) async {
    if (isBusy) return;
    _isLoading = true;
    _error = null;
    _failedMessage = null;
    _messages.clear();
    _conversationId = null;
    notifyListeners();
    try {
      final response =
          await _get('/ai/conversations/${Uri.encodeComponent(id)}/messages');
      final items = _payload(response)['messages'];
      if (_isError(response) || items is! List) {
        _error = _errorMessage(response);
      } else {
        final messages = items
            .map((item) =>
                ChatMessageModel.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        _messages.addAll(messages);
        _conversationId = id;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void startNewConversation() {
    if (isBusy) return;
    _conversationId = null;
    _messages.clear();
    _failedMessage = null;
    _error = null;
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || isBusy) return;
    final message = text.trim();
    _messages.add(ChatMessageModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      content: message,
      isUser: true,
      timestamp: DateTime.now(),
    ));
    await _send(message);
  }

  Future<void> retry() async {
    if (!canRetry) return;
    await _send(_failedMessage!);
  }

  Future<void> _send(String message) async {
    _isTyping = true;
    _error = null;
    _failedMessage = null;
    notifyListeners();
    try {
      final response = await _post(
          '/ai/chat',
          {
            'message': message,
            if (_conversationId != null) 'conversation_id': _conversationId,
          },
          timeout: const Duration(seconds: 40));
      final data = _payload(response);
      final reply = data['reply'] ?? data['balasan'];
      if (_isError(response) || reply is! String) {
        _failedMessage = message;
        _error = _errorMessage(response);
      } else {
        _conversationId =
            data['conversation_id']?.toString() ?? _conversationId;
        _sisaKuotaAi =
            _intValue(data['remaining_quota'] ?? data['sisa_kuota_ai']) ??
                _sisaKuotaAi;
        _messages.add(ChatMessageModel(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          content: reply,
          isUser: false,
          timestamp: DateTime.now(),
        ));
        await _fetchConversations();
      }
    } catch (e) {
      _failedMessage = message;
      _error = e.toString();
    } finally {
      _isTyping = false;
      notifyListeners();
    }
  }

  Map<String, dynamic> _payload(Map<String, dynamic>? response) => {
        if (response?['data'] is Map)
          ...Map<String, dynamic>.from(response!['data']),
        ...?response,
      };

  bool _isError(Map<String, dynamic>? response) =>
      response == null ||
      response['status'] == 'error' ||
      (response['statusCode'] is int && response['statusCode'] >= 400);

  String _errorMessage(Map<String, dynamic>? response) =>
      response?['message']?.toString() ?? 'Gagal memuat percakapan.';

  int? _intValue(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
}
