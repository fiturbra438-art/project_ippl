import 'package:flutter/material.dart';
import '../models/produk.dart';

class ProdukProvider extends ChangeNotifier {
  // Data bersih awal (0 produk katalog)
  final List<ProdukModel> _daftarProduk = [];

  int _selectedUnitFilter = 0; // 0 = Semua
  String _searchQuery = '';

  List<ProdukModel> get daftarProduk {
    return _daftarProduk.where((p) {
      final matchUnit = _selectedUnitFilter == 0 || p.unitId == _selectedUnitFilter;
      final matchQuery = p.nama.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.sku.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchUnit && matchQuery;
    }).toList();
  }

  int get selectedUnitFilter => _selectedUnitFilter;

  void setUnitFilter(int unitId) {
    _selectedUnitFilter = unitId;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void updateStok(int produkId, int penambahan) {
    final idx = _daftarProduk.indexWhere((p) => p.id == produkId);
    if (idx != -1) {
      final p = _daftarProduk[idx];
      _daftarProduk[idx] = ProdukModel(
        id: p.id,
        unitId: p.unitId,
        nama: p.nama,
        sku: p.sku,
        hargaBeli: p.hargaBeli,
        hargaJual: p.hargaJual,
        stok: (p.stok + penambahan).clamp(0, 99999),
        minStok: p.minStok,
      );
      notifyListeners();
    }
  }

  void tambahProduk(ProdukModel produk) {
    _daftarProduk.add(produk);
    notifyListeners();
  }
}
