import 'package:flutter/material.dart';
import '../models/produk.dart';
import '../services/api_service.dart';

typedef ProdukApiPatch = Future<Map<String, dynamic>?> Function(
  String endpoint,
  Map<String, dynamic>? body,
);

class ProdukProvider extends ChangeNotifier {
  ProdukProvider({ProdukApiPatch? patch})
      : _patch = patch ?? ((endpoint, body) => ApiService.patch(endpoint, body));

  final ProdukApiPatch _patch;

  // Data produk yang disinkronkan langsung dari PostgreSQL backend
  List<ProdukModel> _daftarProduk = [];
  bool _isLoading = false;
  String? _lastError;

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
  String? get lastError => _lastError;

  Future<void> fetchProdukFromApi({int? unitId}) async {
    _isLoading = true;
    _lastError = null;
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
      } else if (res != null && res['status'] == 'error') {
        _lastError = res['message'] as String?;
      }
    } catch (e) {
      debugPrint('ProdukProvider.fetchProdukFromApi error: $e');
      _lastError = 'Gagal memuat produk: $e';
    }
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

  Future<bool> updateStok(int produkId, int penambahan) async {
    _lastError = null;
    final idx = _daftarProduk.indexWhere((p) => p.id == produkId);
    if (idx == -1 || penambahan == 0) {
      _lastError = 'Produk atau perubahan stok tidak valid.';
      return false;
    }

    try {
      final product = _daftarProduk[idx];
      final res = await _patch('/produk/$produkId/stok', {
        'unit_id': product.unitId,
        'penambahan': penambahan,
      });
      if (res != null && res['status'] == 'success') {
        _daftarProduk[idx] = ProdukModel(
          id: product.id,
          unitId: product.unitId,
          nama: product.nama,
          sku: product.sku,
          hargaBeli: product.hargaBeli,
          hargaJual: product.hargaJual,
          stok: product.stok + penambahan,
          minStok: product.minStok,
        );
        notifyListeners();
        return true;
      }
      _lastError = res?['message'] as String? ?? 'Gagal menyesuaikan stok.';
    } catch (e) {
      debugPrint('ProdukProvider.updateStok error: $e');
      _lastError = 'Gagal menyesuaikan stok: $e';
    }

    notifyListeners();
    return false;
  }

  Future<String?> importProdukBatch(int unitId, List<Map<String, dynamic>> rows) async {
    _lastError = null;
    try {
      final res = await ApiService.post('/produk/import', {
        'unit_id': unitId,
        'rows': rows,
      });
      if (res != null && res['status'] == 'success') {
        await fetchProdukFromApi(unitId: unitId);
        return null;
      }
      final data = res?['data'];
      if (data is Map && data['errors'] is List && (data['errors'] as List).isNotEmpty) {
        final messages = (data['errors'] as List)
            .take(5)
            .map((error) => 'Baris ${error['baris']}: ${error['pesan']}')
            .join('\n');
        _lastError = messages;
        return messages;
      }
      final message = res?['message'] as String? ?? 'Gagal mengimpor produk.';
      _lastError = message;
      return message;
    } catch (e) {
      debugPrint('ProdukProvider.importProdukBatch error: $e');
      _lastError = 'Gagal mengimpor produk: $e';
      return _lastError;
    }
  }

  void tambahProduk(ProdukModel produk) {
    _daftarProduk.add(produk);
    notifyListeners();
  }

  Future<bool> simpanProdukKeBackend(ProdukModel produk) async {
    _lastError = null;
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
      _lastError = res?['message'] as String? ?? 'Gagal menyimpan produk ke server.';
    } catch (e) {
      debugPrint('ProdukProvider.simpanProdukKeBackend error: $e');
      _lastError = 'Gagal menyimpan produk: $e';
    }

    notifyListeners();
    return false;
  }
}
