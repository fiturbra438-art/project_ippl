import 'package:flutter/material.dart';
import '../models/produk.dart';

class ProdukProvider extends ChangeNotifier {
  final List<ProdukModel> _daftarProduk = [
    ProdukModel(
      id: 1,
      unitId: 1,
      nama: 'Biji Kopi Arabika 1kg',
      sku: 'KOP-ARA-001',
      hargaBeli: 90000,
      hargaJual: 135000,
      stok: 24,
      minStok: 5,
    ),
    ProdukModel(
      id: 2,
      unitId: 1,
      nama: 'Syrup Karamel Gourmet 750ml',
      sku: 'SYR-KRM-002',
      hargaBeli: 65000,
      hargaJual: 95000,
      stok: 4, // Kritis
      minStok: 5,
    ),
    ProdukModel(
      id: 3,
      unitId: 2,
      nama: 'Deterjen Cair Konsentrat 5L',
      sku: 'LND-DET-001',
      hargaBeli: 55000,
      hargaJual: 80000,
      stok: 18,
      minStok: 6,
    ),
    ProdukModel(
      id: 4,
      unitId: 3,
      nama: 'Fast Charger Type-C 30W',
      sku: 'ELK-CHG-003',
      hargaBeli: 45000,
      hargaJual: 89000,
      stok: 35,
      minStok: 8,
    ),
  ];

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
