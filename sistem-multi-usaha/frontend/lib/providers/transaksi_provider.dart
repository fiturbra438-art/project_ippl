import 'package:flutter/material.dart';
import '../models/transaksi.dart';
import '../services/api_service.dart';

class TransaksiProvider extends ChangeNotifier {
  // Data transaksi yang disinkronkan langsung dari PostgreSQL backend
  List<TransaksiModel> _daftarTransaksi = [];
  bool _isLoading = false;
  String? _lastError;

  String _filterJenis = 'Semua';

  List<TransaksiModel> get daftarTransaksi {
    if (_filterJenis == 'Pemasukan') {
      return _daftarTransaksi.where((t) => t.jenis == JenisTransaksi.pemasukan).toList();
    } else if (_filterJenis == 'Pengeluaran') {
      return _daftarTransaksi.where((t) => t.jenis == JenisTransaksi.pengeluaran).toList();
    }
    return _daftarTransaksi;
  }

  bool get isLoading => _isLoading;
  String get filterJenis => _filterJenis;
  String? get lastError => _lastError;

  Future<void> fetchTransaksiFromApi({int? unitId}) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final endpoint = (unitId != null && unitId > 0) ? '/transaksi?unit_id=$unitId' : '/transaksi';
      final res = await ApiService.get(endpoint);
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final list = res['data'] as List;
        _daftarTransaksi = list.map<TransaksiModel>((item) {
          final jenisStr = (item['jenis'] as String? ?? 'pemasukan').toLowerCase();
          final tglStr = item['tanggal'] as String? ?? '';
          return TransaksiModel(
            id: (item['id'] as num).toInt(),
            unitId: (item['unit_id'] as num).toInt(),
            namaUnit: item['nama_unit'] as String? ?? 'Unit Usaha',
            tanggal: DateTime.tryParse(tglStr) ?? DateTime.now(),
            jenis: jenisStr == 'pengeluaran' ? JenisTransaksi.pengeluaran : JenisTransaksi.pemasukan,
            kategori: item['kategori'] as String? ?? 'Umum',
            jumlah: (item['jumlah'] as num?)?.toDouble() ?? 0.0,
            keterangan: item['keterangan'] as String? ?? '',
          );
        }).toList();
      } else if (res != null && res['status'] == 'error') {
        _lastError = res['message'] as String?;
      }
    } catch (e) {
      debugPrint('TransaksiProvider.fetchTransaksiFromApi error: $e');
      _lastError = 'Gagal memuat transaksi: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  void setFilterJenis(String jenis) {
    _filterJenis = jenis;
    notifyListeners();
  }

  Future<bool> catatTransaksiManual({
    required int unitId,
    required JenisTransaksi jenis,
    required String kategori,
    required double jumlah,
  }) async {
    _lastError = null;
    try {
      final response = await ApiService.post('/transaksi', {
        'unit_id': unitId,
        'jenis': jenis.name,
        'kategori': kategori,
        'jumlah': jumlah,
        'keterangan': kategori,
      });
      if (response != null && response['status'] == 'success') {
        await fetchTransaksiFromApi(unitId: unitId);
        return true;
      }
      _lastError = response?['message'] as String? ?? 'Gagal menyimpan transaksi.';
    } catch (error) {
      debugPrint('TransaksiProvider.catatTransaksiManual error: $error');
      _lastError = 'Gagal menyimpan transaksi: $error';
    }
    notifyListeners();
    return false;
  }
}
