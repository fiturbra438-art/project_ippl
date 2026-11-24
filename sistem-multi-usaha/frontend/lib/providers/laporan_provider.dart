import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/laporan.dart';
import '../services/api_service.dart';

class LaporanProvider extends ChangeNotifier {
  String _periodeTerpilih = 'Bulan Ini';
  bool _isLoading = false;
  String? _lastError;

  final List<String> _daftarPeriode = ['Bulan Ini', 'Kuartal Ini', 'Tahun Ini'];

  LaporanSummary _summary = LaporanSummary(
    totalPemasukan: 0,
    totalPengeluaran: 0,
    labaOperasional: 0,
    marginLabaPersen: 0.0,
    omzetKotor: 0,
    diskon: 0,
    refund: 0,
    omzetBersih: 0,
    hpp: 0,
    rincianPengeluaran: [],
    performaUnit: [],
  );

  String get periodeTerpilih => _periodeTerpilih;
  List<String> get daftarPeriode => _daftarPeriode;
  LaporanSummary get summary => _summary;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  Future<void> fetchLaporanFromApi({
    int? unitId,
    DateTime? tanggalMulai,
    DateTime? tanggalAkhir,
    String? metodePembayaran,
    String? statusTransaksi,
  }) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final query = <String, String>{
        if (unitId != null && unitId > 0) 'unit_id': '$unitId',
        if (tanggalMulai != null)
          'tanggal_mulai': DateFormat('yyyy-MM-dd').format(tanggalMulai),
        if (tanggalAkhir != null)
          'tanggal_akhir': DateFormat('yyyy-MM-dd').format(tanggalAkhir),
        if (metodePembayaran != null) 'metode_pembayaran': metodePembayaran,
        if (statusTransaksi != null) 'status_transaksi': statusTransaksi,
      };
      final endpoint = Uri(path: '/laporan/keuangan', queryParameters: query).toString();
      final res = await ApiService.get(endpoint);
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final d = res['data'];
        final pemasukan = (d['total_pemasukan'] as num?)?.toDouble() ?? 0.0;
        final pengeluaran = (d['total_pengeluaran'] as num?)?.toDouble() ?? 0.0;
        final omzetKotor = (d['omzet_kotor'] as num?)?.toDouble() ?? pemasukan;
        final diskon = (d['diskon'] as num?)?.toDouble() ?? 0.0;
        final refund = (d['refund'] as num?)?.toDouble() ?? 0.0;
        final omzetBersih = (d['omzet_bersih'] as num?)?.toDouble() ?? pemasukan;
        final hpp = (d['hpp'] as num?)?.toDouble() ?? 0.0;
        final laba = (pemasukan - pengeluaran - hpp);
        final margin = (d['margin_laba_persen'] as num?)?.toDouble() ?? (pemasukan > 0 ? (laba / pemasukan) * 100 : 0.0);

        final unitList = (d['performa_unit'] as List?) ?? [];
        final performa = unitList.map<PerformaUnitLaporan>((u) {
          final p = (u['pemasukan'] as num?)?.toDouble() ?? 0.0;
          final k = (u['pengeluaran'] as num?)?.toDouble() ?? 0.0;
          return PerformaUnitLaporan(
            namaUnit: u['nama_unit'] as String? ?? 'Unit',
            pendapatan: p,
            pengeluaran: k,
            labaBersih: p - k,
            kontribusiPersen: pemasukan > 0 ? (p / pemasukan) * 100 : 0.0,
          );
        }).toList();

        _summary = LaporanSummary(
          totalPemasukan: pemasukan,
          totalPengeluaran: pengeluaran,
          labaOperasional: laba,
          marginLabaPersen: margin,
          omzetKotor: omzetKotor,
          diskon: diskon,
          refund: refund,
          omzetBersih: omzetBersih,
          hpp: hpp,
          rincianPengeluaran: [],
          performaUnit: performa,
        );
      } else if (res != null && res['status'] == 'error') {
        _lastError = res['message'] as String?;
      } else {
        _lastError = 'Respons laporan tidak valid.';
      }
    } catch (e) {
      debugPrint('LaporanProvider.fetchLaporanFromApi error: $e');
      _lastError = 'Gagal memuat laporan keuangan: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  void setPeriode(String periode) {
    _periodeTerpilih = periode;
    notifyListeners();
  }
}
