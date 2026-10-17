import 'package:flutter/material.dart';
import '../models/gudang_model.dart';

class GudangProvider extends ChangeNotifier {
  final List<TransferStokModel> _daftarTransfer = [
    TransferStokModel(
      id: 1,
      unitAsalId: 1, // Kedai Kopi
      namaUnitAsal: 'Kedai Kopi Bahagia',
      unitTujuanId: 2, // Laundry
      namaUnitTujuan: 'Laundry Bersih Kilat',
      produkId: 3,
      namaProduk: 'Deterjen Cair 5L',
      jumlah: 5,
      waktuKirim: DateTime.now().subtract(const Duration(hours: 3)),
      status: StatusTransfer.pending,
    ),
    TransferStokModel(
      id: 2,
      unitAsalId: 4, // Gudang Pusat
      namaUnitAsal: 'Gudang Pusat Cikarang',
      unitTujuanId: 1,
      namaUnitTujuan: 'Kedai Kopi Bahagia',
      produkId: 1,
      namaProduk: 'Biji Kopi Arabika 1kg',
      jumlah: 20,
      waktuKirim: DateTime.now().subtract(const Duration(days: 1)),
      waktuTerima: DateTime.now().subtract(const Duration(hours: 18)),
      status: StatusTransfer.diterima,
    ),
  ];

  final List<StokOpnameModel> _daftarOpname = [
    StokOpnameModel(
      id: 1,
      unitId: 1,
      namaUnit: 'Kedai Kopi Bahagia',
      namaProduk: 'Syrup Karamel 750ml',
      stokSistem: 5,
      stokFisik: 4,
      alasan: '1 botol tumpah saat persiapan bar',
      tanggal: DateTime.now().subtract(const Duration(days: 2)),
    ),
  ];

  final List<MutasiStokModel> _daftarMutasi = [
    MutasiStokModel(
      id: 1,
      jenis: 'MASUK',
      namaProduk: 'Biji Kopi Arabika 1kg',
      jumlah: 30,
      sumberTujuan: 'Pemasok Kopi Nusantara',
      tanggal: DateTime.now().subtract(const Duration(days: 1)),
    ),
    MutasiStokModel(
      id: 2,
      jenis: 'KELUAR',
      namaProduk: 'Deterjen Cair Konsentrat 5L',
      jumlah: 2,
      sumberTujuan: 'Pemakaian Harian Laundry',
      tanggal: DateTime.now().subtract(const Duration(hours: 6)),
    ),
  ];

  List<TransferStokModel> get daftarTransfer => _daftarTransfer;
  List<StokOpnameModel> get daftarOpname => _daftarOpname;
  List<MutasiStokModel> get daftarMutasi => _daftarMutasi;

  void kirimTransferStok(TransferStokModel transfer) {
    _daftarTransfer.insert(0, transfer);
    notifyListeners();
  }

  void konfirmasiPenerimaan(int id) {
    final idx = _daftarTransfer.indexWhere((t) => t.id == id);
    if (idx != -1) {
      _daftarTransfer[idx].status = StatusTransfer.diterima;
      _daftarTransfer[idx].waktuTerima = DateTime.now();
      notifyListeners();
    }
  }

  void tolakTransfer(int id) {
    final idx = _daftarTransfer.indexWhere((t) => t.id == id);
    if (idx != -1) {
      _daftarTransfer[idx].status = StatusTransfer.ditolak;
      notifyListeners();
    }
  }

  void catatOpname(StokOpnameModel opname) {
    _daftarOpname.insert(0, opname);
    notifyListeners();
  }

  void catatMutasi(MutasiStokModel mutasi) {
    _daftarMutasi.insert(0, mutasi);
    notifyListeners();
  }
}
