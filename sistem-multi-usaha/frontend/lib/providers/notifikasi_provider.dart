import 'package:flutter/material.dart';
import '../models/notifikasi_model.dart';

class NotifikasiProvider extends ChangeNotifier {
  final List<NotifikasiItem> _daftarNotifikasi = [];

  List<NotifikasiItem> get daftarNotifikasi => _daftarNotifikasi;
  int get unreadCount => _daftarNotifikasi.where((n) => !n.isDibaca).length;

  void tambahNotifikasi(NotifikasiItem item) {
    _daftarNotifikasi.insert(0, item);
    notifyListeners();
  }

  void tandaiSemuaDibaca() {
    for (var n in _daftarNotifikasi) {
      n.isDibaca = true;
    }
    notifyListeners();
  }

  void tandaiDibaca(int id) {
    final idx = _daftarNotifikasi.indexWhere((n) => n.id == id);
    if (idx != -1) {
      _daftarNotifikasi[idx].isDibaca = true;
      notifyListeners();
    }
  }

  void hapusNotifikasi(int id) {
    _daftarNotifikasi.removeWhere((n) => n.id == id);
    notifyListeners();
  }
}
