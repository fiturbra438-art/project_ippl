import 'package:flutter/material.dart';
import '../models/usaha.dart';
import '../services/api_service.dart';

class DashboardProvider extends ChangeNotifier {
  // Data ringkasan bisnis yang disinkronkan langsung dari PostgreSQL backend
  List<UsahaModel> _daftarUsaha = [];
  bool _isLoading = false;
  int _selectedNavIndex = 0;
  String? _lastError;

  List<UsahaModel> get daftarUsaha => _daftarUsaha;
  bool get isLoading => _isLoading;
  int get selectedNavIndex => _selectedNavIndex;
  String? get lastError => _lastError;

  DashboardProvider() {
    fetchDashboardSummary();
  }

  Future<void> fetchDashboardSummary() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final res = await ApiService.get('/dashboard/summary');
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final d = res['data'];
        final unitList = (d['unit_performas'] as List?) ?? [];
        _daftarUsaha = unitList.map((item) {
          return UsahaModel(
            id: (item['unit_id'] as num).toInt(),
            nama: item['nama_unit'] as String? ?? '',
            jenisUsaha: item['jenis_usaha'] as String? ?? '',
            lokasi: item['lokasi'] as String? ?? '',
            kategoriPortofolio: item['kategori_portofolio'] as String? ?? 'Star',
            pendapatanBulanIni: (item['total_omzet'] as num?)?.toDouble() ?? 0.0,
            pengeluaranBulanIni: 0.0,
            pertumbuhanPersen: 0.0,
            status: true,
            hasPos: true,
          );
        }).toList();
      } else if (res != null && res['status'] == 'error') {
        _lastError = res['message'] as String?;
      }
    } catch (e) {
      debugPrint('DashboardProvider.fetchDashboardSummary error: $e');
      _lastError = 'Gagal memuat ringkasan dashboard: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  double get totalPendapatan =>
      _daftarUsaha.fold(0, (sum, item) => sum + item.pendapatanBulanIni);

  double get totalPengeluaran =>
      _daftarUsaha.fold(0, (sum, item) => sum + item.pengeluaranBulanIni);

  double get totalLabaBersih => totalPendapatan - totalPengeluaran;

  void setNavIndex(int index) {
    _selectedNavIndex = index;
    notifyListeners();
  }
}
