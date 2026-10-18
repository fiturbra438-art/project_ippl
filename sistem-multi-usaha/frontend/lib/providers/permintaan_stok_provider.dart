import 'package:flutter/material.dart';
import '../models/permintaan_stok_model.dart';

class PermintaanStokProvider extends ChangeNotifier {
  // Data bersih awal (0 permintaan stok)
  final List<PermintaanStokModel> _daftarPermintaan = [];

  List<PermintaanStokModel> get daftarPermintaan => _daftarPermintaan;

  void ajukanPermintaan(PermintaanStokModel permintaan) {
    _daftarPermintaan.insert(0, permintaan);
    notifyListeners();
  }

  void setujuiPermintaan(int id) {
    final idx = _daftarPermintaan.indexWhere((p) => p.id == id);
    if (idx != -1) {
      _daftarPermintaan[idx].status = StatusPermintaanStok.disetujui;
      notifyListeners();
    }
  }

  void tolakPermintaan(int id) {
    final idx = _daftarPermintaan.indexWhere((p) => p.id == id);
    if (idx != -1) {
      _daftarPermintaan[idx].status = StatusPermintaanStok.ditolak;
      notifyListeners();
    }
  }
}
