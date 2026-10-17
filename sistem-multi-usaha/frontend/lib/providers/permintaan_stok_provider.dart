import 'package:flutter/material.dart';
import '../models/permintaan_stok_model.dart';

class PermintaanStokProvider extends ChangeNotifier {
  final List<PermintaanStokModel> _daftarPermintaan = [
    PermintaanStokModel(
      id: 1,
      unitId: 1,
      namaUnit: 'Kedai Kopi Bahagia',
      pemohon: 'Siti Rahma (Manager)',
      namaProduk: 'Biji Kopi Arabika 1kg',
      jumlahDiminta: 40,
      alasan: 'Stok menipis jelang akhir pekan dan promo paket kopi',
      waktuPengajuan: DateTime.now().subtract(const Duration(hours: 4)),
      status: StatusPermintaanStok.pending,
    ),
    PermintaanStokModel(
      id: 2,
      unitId: 2,
      namaUnit: 'Laundry Bersih Kilat',
      pemohon: 'Manager Laundry',
      namaProduk: 'Deterjen Cair Konsentrat 5L',
      jumlahDiminta: 15,
      alasan: 'Order borongan hotel bertambah',
      waktuPengajuan: DateTime.now().subtract(const Duration(days: 1)),
      status: StatusPermintaanStok.disetujui,
    ),
  ];

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
