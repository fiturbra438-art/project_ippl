import 'package:flutter/material.dart';
import '../models/transaksi.dart';

class TransaksiProvider extends ChangeNotifier {
  // Data bersih awal (0 transaksi kas)
  List<TransaksiModel> _daftarTransaksi = [];

  String _filterJenis = 'Semua';

  List<TransaksiModel> get daftarTransaksi {
    if (_filterJenis == 'Pemasukan') {
      return _daftarTransaksi.where((t) => t.jenis == JenisTransaksi.pemasukan).toList();
    } else if (_filterJenis == 'Pengeluaran') {
      return _daftarTransaksi.where((t) => t.jenis == JenisTransaksi.pengeluaran).toList();
    }
    return _daftarTransaksi;
  }

  String get filterJenis => _filterJenis;

  void setFilterJenis(String jenis) {
    _filterJenis = jenis;
    notifyListeners();
  }

  void tambahTransaksi(TransaksiModel transaksi) {
    _daftarTransaksi.insert(0, transaksi);
    notifyListeners();
  }
}
