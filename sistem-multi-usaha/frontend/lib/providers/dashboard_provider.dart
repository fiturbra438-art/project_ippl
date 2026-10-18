import 'package:flutter/material.dart';
import '../models/usaha.dart';

class DashboardProvider extends ChangeNotifier {
  // Data bersih awal (0 unit)
  List<UsahaModel> _daftarUsaha = [];

  int _selectedNavIndex = 0;

  List<UsahaModel> get daftarUsaha => _daftarUsaha;
  int get selectedNavIndex => _selectedNavIndex;

  double get totalPendapatan =>
      _daftarUsaha.fold(0, (sum, item) => sum + item.pendapatanBulanIni);

  double get totalPengeluaran =>
      _daftarUsaha.fold(0, (sum, item) => sum + item.pengeluaranBulanIni);

  double get totalLabaBersih => totalPendapatan - totalPengeluaran;

  void setNavIndex(int index) {
    _selectedNavIndex = index;
    notifyListeners();
  }
}
