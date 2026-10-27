import 'package:flutter/material.dart';
import '../models/laporan.dart';

class LaporanProvider extends ChangeNotifier {
  String _periodeTerpilih = 'Bulan Ini';

  final List<String> _daftarPeriode = ['Bulan Ini', 'Kuartal Ini', 'Tahun Ini'];

  LaporanSummary _summary = LaporanSummary(
    totalPemasukan: 0,
    totalPengeluaran: 0,
    labaOperasional: 0,
    marginLabaPersen: 0.0,
    rincianPengeluaran: [],
    performaUnit: [],
  );

  String get periodeTerpilih => _periodeTerpilih;
  List<String> get daftarPeriode => _daftarPeriode;
  LaporanSummary get summary => _summary;

  void setSummary(LaporanSummary newSummary) {
    _summary = newSummary;
    notifyListeners();
  }

  void setPeriode(String periode) {
    _periodeTerpilih = periode;
    notifyListeners();
  }
}
