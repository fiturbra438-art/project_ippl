import 'package:flutter/material.dart';
import '../models/chat_model.dart';
import '../services/api_service.dart';

class ChatAiProvider extends ChangeNotifier {
  final List<ChatMessageModel> _messages = [
    ChatMessageModel(
      id: '1',
      content: 'Halo! Saya Asisten AI Finansial & Portofolio Bisnis Anda. Saya terhubung langsung dengan data keuangan cabang, kasir POS, dan inventaris gudang Anda. Ada yang bisa saya bantu analisa?',
      isUser: false,
      timestamp: DateTime.now(),
      suggestions: [
        'Berapa total omzet usaha saya saat ini?',
        'Apakah ada produk yang stoknya kritis?',
        'Berikan saran strategi alokasi modal',
      ],
    ),
  ];

  bool _isTyping = false;
  int _sisaKuotaAi = 250;

  List<ChatMessageModel> get messages => _messages;
  bool get isTyping => _isTyping;
  int get sisaKuotaAi => _sisaKuotaAi;

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMsg = ChatMessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    _messages.add(userMsg);
    _isTyping = true;
    notifyListeners();

    String reply = '';

    try {
      // Panggil backend Core Rust endpoint AI
      final res = await ApiService.post('/ai/chat', {
        'pesan': text,
      });

      if (res != null && res['status'] == 'success' && res['data'] != null) {
        reply = res['data']['balasan'] as String? ?? 'Tidak ada respon dari AI.';
        if (res['data']['sisa_kuota_ai'] != null) {
          _sisaKuotaAi = res['data']['sisa_kuota_ai'] as int;
        }
      } else if (res != null && res['message'] != null) {
        reply = '⚠️ ${res['message']}';
      } else {
        // Fallback jika backend offline/tidak terjangkau
        reply = _localFallbackReply(text);
      }
    } catch (_) {
      reply = _localFallbackReply(text);
    }

    _messages.add(
      ChatMessageModel(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        content: reply,
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    _isTyping = false;
    notifyListeners();
  }

  String _localFallbackReply(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('omzet') || lower.contains('pendapatan')) {
      return 'Total omzet bisnis Anda terpantau langsung melalui sistem konsolidasi POS dan pencatatan kas unit usaha.';
    } else if (lower.contains('stok') || lower.contains('kritis')) {
      return 'Pengecekan stok otomatis aktif. Barang yang mencapai batas minimum akan langsung terdata di Peringatan Stok Kritis.';
    } else {
      return 'Saya siap membantu menganalisis kesehatan finansial, evaluasi cabang, maupun efisiensi biaya usaha Anda.';
    }
  }
}

