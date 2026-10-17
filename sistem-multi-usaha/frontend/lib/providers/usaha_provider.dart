import 'package:flutter/material.dart';
import '../models/usaha.dart';

class UsahaProvider extends ChangeNotifier {
  List<UsahaModel> _daftarUsaha = [
    UsahaModel(
      id: 1,
      nama: 'Kedai Kopi Bahagia',
      jenisUsaha: 'F&B / Kafe',
      lokasi: 'Jl. Merdeka No. 12',
      kategoriPortofolio: 'Star',
      pendapatanBulanIni: 48500000,
      pengeluaranBulanIni: 31200000,
      pertumbuhanPersen: 14.8,
    ),
    UsahaModel(
      id: 2,
      nama: 'Laundry Bersih Kilat',
      jenisUsaha: 'Jasa Cuci',
      lokasi: 'Jl. Pemuda No. 45',
      kategoriPortofolio: 'Cash Cow',
      pendapatanBulanIni: 32000000,
      pengeluaranBulanIni: 15400000,
      pertumbuhanPersen: 5.2,
    ),
    UsahaModel(
      id: 3,
      nama: 'Toko Elektronik Digital',
      jenisUsaha: 'Retail / Gadget',
      lokasi: 'Mall Sentral Lt. 2',
      kategoriPortofolio: 'Question Mark',
      pendapatanBulanIni: 78900000,
      pengeluaranBulanIni: 71000000,
      pertumbuhanPersen: 22.4,
    ),
    UsahaModel(
      id: 4,
      nama: 'Distribusi Bahan Pokok',
      jenisUsaha: 'Gudang & Grosir',
      lokasi: 'Kawasan Industri Blok C',
      kategoriPortofolio: 'Cash Cow',
      pendapatanBulanIni: 125000000,
      pengeluaranBulanIni: 98000000,
      pertumbuhanPersen: 8.1,
    ),
  ];

  String _searchQuery = '';
  String _filterKategori = 'Semua';

  List<UsahaModel> get daftarUsaha {
    return _daftarUsaha.where((item) {
      final matchesSearch = item.nama.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.jenisUsaha.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.lokasi.toLowerCase().contains(_searchQuery.toLowerCase());
      
      final matchesCategory = _filterKategori == 'Semua' || item.kategoriPortofolio == _filterKategori;
      
      return matchesSearch && matchesCategory;
    }).toList();
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
}
