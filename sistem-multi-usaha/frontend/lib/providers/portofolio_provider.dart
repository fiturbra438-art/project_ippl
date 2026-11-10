import 'package:flutter/material.dart';
import '../models/portofolio.dart';
import '../services/api_service.dart';

class PortofolioProvider extends ChangeNotifier {
  final List<BCGItem> _items = [];
  final List<String> _kebijakanAlokasi = [];
  bool _isLoading = false;
  String? _lastError;

  List<BCGItem> get items => _items;
  List<String> get kebijakanAlokasi => _kebijakanAlokasi;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  Future<void> fetchPortfolio() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final res = await ApiService.get('/ai/portfolio');
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        final list = (data['items'] as List?) ?? [];
        _items
          ..clear()
          ..addAll(list.map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            return BCGItem(
              id: (map['id'] as num).toInt(),
              namaUsaha: map['nama_usaha'] as String? ?? 'Unit Usaha',
              kategori: map['kategori'] as String? ?? 'Star',
              growthRate: (map['growth_rate'] as num?)?.toDouble() ?? 0,
              marketShare: (map['market_share'] as num?)?.toDouble() ?? 0,
              arusKas: (map['arus_kas'] as num?)?.toDouble() ?? 0,
              rekomendasi: map['rekomendasi'] as String? ?? '',
            );
          }));

        final policies = (data['kebijakan_alokasi'] as List?) ?? [];
        _kebijakanAlokasi
          ..clear()
          ..addAll(policies.map((policy) => policy.toString()));
      } else {
        _lastError = res?['message'] as String? ?? 'Gagal memuat portofolio.';
      }
    } catch (e) {
      debugPrint('PortofolioProvider.fetchPortfolio error: $e');
      _lastError = 'Gagal memuat portofolio: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  List<BCGItem> getByKategori(String kategori) =>
      _items.where((i) => i.kategori == kategori).toList();

  void setItems(List<BCGItem> items) {
    _items
      ..clear()
      ..addAll(items);
    notifyListeners();
  }
}
