import 'package:flutter/material.dart';
import '../models/usaha.dart';
import '../services/api_service.dart';

class UsahaProvider extends ChangeNotifier {
  // Data unit usaha yang disinkronkan langsung dengan PostgreSQL
  List<UsahaModel> _daftarUsaha = [];
  String? _lastError;

  String? get lastError => _lastError;

  UsahaProvider() {
    fetchUsahaFromApi();
  }

  Future<void> fetchUsahaFromApi() async {
    _lastError = null;
    try {
      final res = await ApiService.get('/usaha');
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final list = res['data'] as List;
        _daftarUsaha = list.map((item) {
          return UsahaModel(
            id: item['id'] as int,
            nama: item['nama'] as String? ?? '',
            jenisUsaha: item['jenis_usaha'] as String? ?? '',
            lokasi: item['lokasi'] as String? ?? '',
            kategoriPortofolio: item['kategori_portofolio'] as String? ?? 'Star',
            pendapatanBulanIni: (item['pendapatan_bulan_ini'] as num?)?.toDouble() ?? 0.0,
            pengeluaranBulanIni: (item['pengeluaran_bulan_ini'] as num?)?.toDouble() ?? 0.0,
            pertumbuhanPersen: (item['pertumbuhan_persen'] as num?)?.toDouble() ?? 0.0,
            status: item['status'] as bool? ?? true,
            hasPos: item['has_pos'] as bool? ?? true,
          );
        }).toList();
        notifyListeners();
      } else if (res != null && res['status'] == 'error') {
        _lastError = res['message'] as String?;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('UsahaProvider.fetchUsahaFromApi error: $e');
      _lastError = 'Gagal memuat unit usaha: $e';
      notifyListeners();
    }
  }

  String _searchQuery = '';
  String _filterKategori = 'Semua';

  List<UsahaModel> get rawDaftarUsaha => _daftarUsaha;

  List<UsahaModel> get daftarUsaha {
    return _daftarUsaha.where((item) {
      final matchesSearch = item.nama.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.jenisUsaha.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.lokasi.toLowerCase().contains(_searchQuery.toLowerCase());
      
      final matchesCategory = _filterKategori == 'Semua' || item.kategoriPortofolio == _filterKategori;
      
      return matchesSearch && matchesCategory;
    }).toList();
  }

  // Filter unit yang hanya diizinkan untuk akun karyawan tertentu (Owner & Auditor bisa akses semua)
  List<UsahaModel> getDaftarUsahaForUser(List<int> unitAksesIds, bool isOwnerOrAuditor) {
    if (isOwnerOrAuditor || unitAksesIds.isEmpty) {
      return daftarUsaha;
    }
    return daftarUsaha.where((u) => unitAksesIds.contains(u.id)).toList();
  }

  String get searchQuery => _searchQuery;
  String get filterKategori => _filterKategori;

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setFilterKategori(String kategori) {
    _filterKategori = kategori;
    notifyListeners();
  }

  Future<void> tambahUsaha(UsahaModel usaha) async {
    _lastError = null;
    try {
      final res = await ApiService.post('/usaha', {
        'nama': usaha.nama,
        'jenis_usaha': usaha.jenisUsaha,
        'lokasi': usaha.lokasi,
        'kategori_portofolio': usaha.kategoriPortofolio,
        'has_pos': usaha.hasPos,
      });
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        await fetchUsahaFromApi();
      } else {
        _lastError = res?['message'] as String? ?? 'Gagal menambah unit usaha.';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('UsahaProvider.tambahUsaha error: $e');
      _lastError = 'Gagal menambah unit usaha: $e';
      notifyListeners();
    }
  }

  Future<void> hapusUsaha(int id) async {
    _lastError = null;
    try {
      final ok = await ApiService.delete('/usaha/$id');
      if (ok) {
        _daftarUsaha.removeWhere((item) => item.id == id);
        notifyListeners();
      } else {
        _lastError = 'Gagal menghapus unit usaha di server.';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('UsahaProvider.hapusUsaha error: $e');
      _lastError = 'Gagal menghapus unit usaha: $e';
      notifyListeners();
    }
  }

  Future<void> toggleHasPos(int id) async {
    _lastError = null;
    final idx = _daftarUsaha.indexWhere((item) => item.id == id);
    if (idx != -1) {
      try {
        final res = await ApiService.patch('/usaha/$id/toggle-pos');
        if (res != null && res['status'] == 'success') {
          final u = _daftarUsaha[idx];
          _daftarUsaha[idx] = UsahaModel(
            id: u.id,
            nama: u.nama,
            jenisUsaha: u.jenisUsaha,
            lokasi: u.lokasi,
            kategoriPortofolio: u.kategoriPortofolio,
            pendapatanBulanIni: u.pendapatanBulanIni,
            pengeluaranBulanIni: u.pengeluaranBulanIni,
            pertumbuhanPersen: u.pertumbuhanPersen,
            status: u.status,
            hasPos: !u.hasPos,
          );
          notifyListeners();
        } else {
          _lastError = res?['message'] as String? ?? 'Gagal mengubah status POS.';
          notifyListeners();
        }
      } catch (e) {
        debugPrint('UsahaProvider.toggleHasPos error: $e');
        _lastError = 'Gagal mengubah status POS: $e';
        notifyListeners();
      }
    }
  }
}
