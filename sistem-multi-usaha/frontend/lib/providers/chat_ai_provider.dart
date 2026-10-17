import 'package:flutter/material.dart';
import '../models/chat_model.dart';

class ChatAiProvider extends ChangeNotifier {
  final List<ChatMessageModel> _messages = [
    ChatMessageModel(
      id: '1',
      content: 'Halo! Saya Asisten AI Finansial & Portofolio Anda. Anda bisa menanyakan analisis performa cabang, evaluasi arus kas, maupun saran alokasi modal BCG.',
      isUser: false,
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      suggestions: [
        'Bagaimana performa Kedai Kopi bulan ini?',
        'Berapa alokasi modal ideal untuk ekspansi?',
        'Unit bisnis mana yang paling hemat biaya?',
      ],
    ),
  ];

  bool _isTyping = false;

  List<ChatMessageModel> get messages => _messages;
  bool get isTyping => _isTyping;

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

    await Future.delayed(const Duration(milliseconds: 900));

    String reply = '';
    final lower = text.toLowerCase();
    if (lower.contains('kopi') || lower.contains('kedai')) {
      reply = 'Kedai Kopi Bahagia (Star) mencatatkan pendapatan Rp 48,500,000 dengan laba bersih Rp 17,300,000 (margin 35.7%). Pertumbuhannya mencapai +14.8%, sangat disarankan untuk ekspansi varian produk sore hari.';
    } else if (lower.contains('modal') || lower.contains('alokasi') || lower.contains('bcg')) {
      reply = 'Berdasarkan BCG Matrix, Laundry Bersih Kilat menghasilkan surplus kas konsisten (Cash Cow). Rekomendasi: Alihkan 20% (± Rp 3.3jt) ke Toko Elektronik Digital (Question Mark) untuk pemasaran digital dan stok barang fast-moving.';
    } else if (lower.contains('hemat') || lower.contains('biaya') || lower.contains('pengeluaran')) {
      reply = 'Unit paling efisien adalah Laundry Bersih Kilat dengan rasio pengeluaran hanya 48% dari omzet, berbanding Toko Elektronik yang rasio biayanya 90%.';
    } else {
      reply = 'Berdasarkan data keuangan multi-usaha terkini: Total pendapatan agregat mencapai Rp 159,400,000 dengan margin laba 26.2%. Arus kas berada di level sehat dan siap untuk ekspansi kuartal depan.';
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
}
