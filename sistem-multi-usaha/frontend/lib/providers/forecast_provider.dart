import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class ForecastDataPoint {
  final String periode;
  final double aktual;
  final double prediksi;
  final double batasBawah;
  final double batasAtas;

  ForecastDataPoint({
    required this.periode,
    this.aktual = 0,
    required this.prediksi,
    required this.batasBawah,
    required this.batasAtas,
  });
}

class ForecastUnit {
  final int id;
  final String nama;

  ForecastUnit({required this.id, required this.nama});
}

class ForecastProvider extends ChangeNotifier {
  int _selectedUnitId = 0;
  final List<ForecastUnit> _units = [];
  final Map<int, List<ForecastDataPoint>> _forecastMap = {};
  bool _isLoading = false;
  String? _lastError;

  int get selectedUnitId => _selectedUnitId;
  List<ForecastUnit> get units => _units;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  List<ForecastDataPoint> get currentForecast =>
      _forecastMap[_selectedUnitId] ?? [];

  Future<void> load() async {
    await fetchUnits();
    await fetchForecast();
  }

  Future<void> fetchUnits() async {
    try {
      final res = await ApiService.get('/usaha');
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final list = res['data'] as List;
        _units
          ..clear()
          ..addAll(list.map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            return ForecastUnit(
              id: (map['id'] as num).toInt(),
              nama: map['nama'] as String? ?? 'Unit Usaha',
            );
          }));
        if (_selectedUnitId == 0 && _units.isNotEmpty) {
          _selectedUnitId = _units.first.id;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('ForecastProvider.fetchUnits error: $e');
      _lastError = 'Gagal memuat daftar unit usaha: $e';
      notifyListeners();
    }
  }

  Future<void> fetchForecast([int? unitId]) async {
    final id = unitId ?? _selectedUnitId;
    if (id == 0) return;

    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final res = await ApiService.get('/ai/forecast/$id');
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        final proyeksi = (data['proyeksi'] as List?) ?? [];
        final points = proyeksi.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return ForecastDataPoint(
            periode: _periodeLabel(map['tanggal']),
            prediksi: (map['prediksi_penjualan'] as num?)?.toDouble() ?? 0,
            batasBawah: (map['batas_bawah'] as num?)?.toDouble() ?? 0,
            batasAtas: (map['batas_atas'] as num?)?.toDouble() ?? 0,
          );
        }).toList();
        _forecastMap[id] = points;
      } else {
        _lastError = res?['message'] as String? ?? 'Gagal memuat forecast.';
      }
    } catch (e) {
      debugPrint('ForecastProvider.fetchForecast error: $e');
      _lastError = 'Gagal memuat forecast: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  void setForecast(int unitId, List<ForecastDataPoint> points) {
    _forecastMap[unitId] = points;
    notifyListeners();
  }

  void selectUnit(int id) {
    if (_selectedUnitId == id) return;
    _selectedUnitId = id;
    notifyListeners();
    fetchForecast(id);
  }

  String _periodeLabel(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '-';
    return DateFormat('dd MMM').format(parsed);
  }
}
