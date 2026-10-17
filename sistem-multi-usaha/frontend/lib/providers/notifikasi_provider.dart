import 'package:flutter/material.dart';
import '../models/notifikasi_model.dart';

class NotifikasiProvider extends ChangeNotifier {
  final List<NotifikasiItem> _daftarNotifikasi = [
    NotifikasiItem(
      id: 1,
      judul: '⚠️ Peringatan Stok Minimum',
      pesan: 'Syrup Karamel Gourmet 750ml tersisa 4 botol di Kedai Kopi (batas minimum 5). Segera restok.',
      jenis: JenisNotifikasi.stokMenipis,
      waktu: DateTime.now().subtract(const Duration(minutes: 15)),
      isDibaca: false,
    ),
    NotifikasiItem(
      id: 2,
      judul: '🚨 Deteksi Anomali Pemakaian Bahan',
      pesan: 'Cabang 1 menggunakan biji kopi 42% lebih banyak dibanding Cabang 2 per cup. Potensi kebocoran Rp 4.2jt/bln.',
      jenis: JenisNotifikasi.anomali,
      waktu: DateTime.now().subtract(const Duration(hours: 2)),
      isDibaca: false,
    ),
    NotifikasiItem(
      id: 3,
      judul: '💡 Rekomendasi Realokasi Stok AI Baru',
      pesan: 'AI merekomendasikan pemindahan 15 unit Fast Charger dari Toko Elektronik ke Kedai Kopi untuk mencegah dead-stock.',
      jenis: JenisNotifikasi.rekomendasiAi,
      waktu: DateTime.now().subtract(const Duration(hours: 5)),
      isDibaca: false,
    ),
    NotifikasiItem(
      id: 4,
      judul: '📦 Permintaan Transfer Stok Baru',
      pesan: 'Kedai Kopi Bahagia mengirimkan 5 botol Deterjen ke Laundry Bersih Kilat. Menunggu konfirmasi penerimaan.',
      jenis: JenisNotifikasi.transferStok,
      waktu: DateTime.now().subtract(const Duration(hours: 8)),
      isDibaca: true,
    ),
  ];

  List<NotifikasiItem> get daftarNotifikasi => _daftarNotifikasi;
  int get unreadCount => _daftarNotifikasi.where((n) => !n.isDibaca).length;

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
}
