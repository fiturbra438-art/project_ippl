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

  final Map<int, List<ForecastDataPoint>> _forecastMap = {};

  int get selectedUnitId => _selectedUnitId;
  List<ForecastDataPoint> get currentForecast => _forecastMap[_selectedUnitId] ?? [];

  void setForecast(int unitId, List<ForecastDataPoint> points) {
    _forecastMap[unitId] = points;
    notifyListeners();
  }

  void selectUnit(int id) {
    _selectedUnitId = id;
    notifyListeners();
  }
}
