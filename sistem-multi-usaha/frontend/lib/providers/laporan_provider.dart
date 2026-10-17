import 'package:flutter/material.dart';
import '../models/laporan.dart';

class LaporanProvider extends ChangeNotifier {
  String _periodeTerpilih = 'Bulan Ini';

  final List<String> _daftarPeriode = ['Bulan Ini', 'Kuartal Ini', 'Tahun Ini'];

  final LaporanSummary _summary = LaporanSummary(
    totalPemasukan: 159400000,
    totalPengeluaran: 117600000,
    labaOperasional: 41800000,
    marginLabaPersen: 26.2,
    rincianPengeluaran: [
      KategoriPengeluaran(nama: 'Bahan Baku & Persediaan', nominal: 68000000, persen: 57.8),
      KategoriPengeluaran(nama: 'Gaji Karyawan', nominal: 28500000, persen: 24.2),
      KategoriPengeluaran(nama: 'Sewa Tempat & Utilitas', nominal: 14200000, persen: 12.1),
      KategoriPengeluaran(nama: 'Pemasaran & Operasional', nominal: 6900000, persen: 5.9),
    ],
    performaUnit: [
      PerformaUnitLaporan(
        namaUnit: 'Kedai Kopi Bahagia',
        pendapatan: 48500000,
        pengeluaran: 31200000,
        labaBersih: 17300000,
        kontribusiPersen: 41.4,
      ),
      PerformaUnitLaporan(
        namaUnit: 'Laundry Bersih Kilat',
        pendapatan: 32000000,
        pengeluaran: 15400000,
        labaBersih: 16600000,
        kontribusiPersen: 39.7,
      ),
      PerformaUnitLaporan(
        namaUnit: 'Toko Elektronik Digital',
        pendapatan: 78900000,
        pengeluaran: 71000000,
        labaBersih: 7900000,
        kontribusiPersen: 18.9,
      ),
    ],
  );

  String get periodeTerpilih => _periodeTerpilih;
  List<String> get daftarPeriode => _daftarPeriode;
  LaporanSummary get summary => _summary;

  void setPeriode(String periode) {
    _periodeTerpilih = periode;
    notifyListeners();
  }
}
