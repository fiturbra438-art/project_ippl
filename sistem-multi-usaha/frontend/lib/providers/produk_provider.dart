import 'package:flutter/material.dart';
import '../models/produk.dart';
import '../services/api_service.dart';

class ProdukProvider extends ChangeNotifier {
  // Data produk yang disinkronkan langsung dari PostgreSQL backend
  List<ProdukModel> _daftarProduk = [];
  bool _isLoading = false;

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

  bool get isLoading => _isLoading;
  int get selectedUnitFilter => _selectedUnitFilter;

  Future<void> fetchProdukFromApi({int? unitId}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final endpoint = (unitId != null && unitId > 0) ? '/produk?unit_id=$unitId' : '/produk';
      final res = await ApiService.get(endpoint);
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final list = res['data'] as List;
        _daftarProduk = list.map((item) {
          return ProdukModel(
            id: (item['id'] as num).toInt(),
            unitId: (item['unit_id'] as num).toInt(),
            nama: item['nama'] as String? ?? '',
            sku: item['sku'] as String? ?? '',
            hargaBeli: (item['harga_beli'] as num?)?.toDouble() ?? 0.0,
            hargaJual: (item['harga_jual'] as num?)?.toDouble() ?? 0.0,
            stok: (item['stok'] as num?)?.toInt() ?? 0,
            minStok: (item['min_stok'] as num?)?.toInt() ?? 5,
          );
        }).toList();
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

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

  Future<bool> simpanProdukKeBackend(ProdukModel produk) async {
    try {
      final res = await ApiService.post('/produk', {
        'unit_id': produk.unitId,
        'nama': produk.nama,
        'sku': produk.sku,
        'harga_beli': produk.hargaBeli,
        'harga_jual': produk.hargaJual,
        'stok': produk.stok,
        'min_stok': produk.minStok,
      });

      if (res != null && res['status'] == 'success') {
        final d = res['data'];
        final p = d != null
            ? ProdukModel(
                id: (d['id'] as num).toInt(),
                unitId: (d['unit_id'] as num).toInt(),
                nama: d['nama'] as String,
                sku: d['sku'] as String,
                hargaBeli: (d['harga_beli'] as num).toDouble(),
                hargaJual: (d['harga_jual'] as num).toDouble(),
                stok: (d['stok'] as num).toInt(),
                minStok: (d['min_stok'] as num).toInt(),
              )
            : produk;
        _daftarProduk.add(p);
        notifyListeners();
        return true;
      }
    } catch (_) {}

    // Fallback lokal
    _daftarProduk.add(produk);
    notifyListeners();
    return true;
  }
}
