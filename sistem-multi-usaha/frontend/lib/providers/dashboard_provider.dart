import 'package:flutter/material.dart';
import '../models/usaha.dart';

class DashboardProvider extends ChangeNotifier {
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
  ];

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
