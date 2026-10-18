import 'package:flutter/material.dart';
import '../models/usaha.dart';

class UsahaProvider extends ChangeNotifier {
  // Data bersih awal (0 unit usaha, diinput oleh pengguna)
  List<UsahaModel> _daftarUsaha = [];

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

  void tambahUsaha(UsahaModel usaha) {
    _daftarUsaha.add(usaha);
    notifyListeners();
  }

  void hapusUsaha(int id) {
    _daftarUsaha.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void toggleHasPos(int id) {
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
    }
  }
}
