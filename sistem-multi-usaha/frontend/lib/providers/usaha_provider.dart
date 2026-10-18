import 'package:flutter/material.dart';
import '../models/usaha.dart';
import '../services/api_service.dart';

class UsahaProvider extends ChangeNotifier {
  // Data unit usaha yang disinkronkan langsung dengan PostgreSQL
  List<UsahaModel> _daftarUsaha = [];

  UsahaProvider() {
    fetchUsahaFromApi();
  }

  Future<void> fetchUsahaFromApi() async {
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
      }
    } catch (_) {}
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
    _daftarUsaha.add(usaha);
    notifyListeners();

    try {
      final res = await ApiService.post('/usaha', {
        'nama': usaha.nama,
        'jenis_usaha': usaha.jenisUsaha,
        'lokasi': usaha.lokasi,
        'kategori_portofolio': usaha.kategoriPortofolio,
        'has_pos': usaha.hasPos,
      });
      if (res != null && res['data'] != null) {
        await fetchUsahaFromApi();
      }
    } catch (_) {}
  }

  Future<void> hapusUsaha(int id) async {
    _daftarUsaha.removeWhere((item) => item.id == id);
    notifyListeners();

    try {
      await ApiService.delete('/usaha/$id');
    } catch (_) {}
  }

  Future<void> toggleHasPos(int id) async {
    final idx = _daftarUsaha.indexWhere((item) => item.id == id);
    if (idx != -1) {
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

      try {
        await ApiService.patch('/usaha/$id/toggle-pos');
      } catch (_) {}
    }
  }
}
