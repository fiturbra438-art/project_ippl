import 'package:flutter/material.dart';

class ForecastDataPoint {
  final String periode; // misal: 'Bln +1', 'Bln +2'
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

class ForecastProvider extends ChangeNotifier {
  int _selectedUnitId = 1;

  final Map<int, List<ForecastDataPoint>> _forecastMap = {
    1: [
      ForecastDataPoint(periode: 'Nov', aktual: 48500000, prediksi: 48500000, batasBawah: 46000000, batasAtas: 51000000),
      ForecastDataPoint(periode: 'Des', prediksi: 54200000, batasBawah: 50500000, batasAtas: 58000000),
      ForecastDataPoint(periode: 'Jan', prediksi: 57800000, batasBawah: 52000000, batasAtas: 62500000),
      ForecastDataPoint(periode: 'Feb', prediksi: 61500000, batasBawah: 55000000, batasAtas: 67000000),
    ],
    2: [
      ForecastDataPoint(periode: 'Nov', aktual: 32000000, prediksi: 32000000, batasBawah: 30000000, batasAtas: 34000000),
      ForecastDataPoint(periode: 'Des', prediksi: 33500000, batasBawah: 31000000, batasAtas: 35500000),
      ForecastDataPoint(periode: 'Jan', prediksi: 34200000, batasBawah: 32000000, batasAtas: 36800000),
      ForecastDataPoint(periode: 'Feb', prediksi: 35000000, batasBawah: 32500000, batasAtas: 37500000),
    ],
  };

  int get selectedUnitId => _selectedUnitId;
  List<ForecastDataPoint> get currentForecast => _forecastMap[_selectedUnitId] ?? _forecastMap[1]!;

  void selectUnit(int id) {
    _selectedUnitId = id;
    notifyListeners();
  }
}
