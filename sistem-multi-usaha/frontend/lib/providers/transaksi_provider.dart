import 'package:flutter/material.dart';
import '../models/transaksi.dart';

class TransaksiProvider extends ChangeNotifier {
  List<TransaksiModel> _daftarTransaksi = [
    TransaksiModel(
      id: 1,
      unitId: 1,
      namaUnit: 'Kedai Kopi Bahagia',
      tanggal: DateTime.now().subtract(const Duration(hours: 2)),
      jenis: JenisTransaksi.pemasukan,
      kategori: 'Penjualan Kopi & Makanan',
      jumlah: 1850000,
      keterangan: 'Penjualan shift siang',
    ),
    TransaksiModel(
      id: 2,
      unitId: 2,
      namaUnit: 'Laundry Bersih Kilat',
      tanggal: DateTime.now().subtract(const Duration(hours: 5)),
      jenis: JenisTransaksi.pemasukan,
      kategori: 'Jasa Cuci Kiloan',
      jumlah: 750000,
      keterangan: 'Paket langganan bulanan',
    ),
    TransaksiModel(
      id: 3,
      unitId: 1,
      namaUnit: 'Kedai Kopi Bahagia',
      tanggal: DateTime.now().subtract(const Duration(days: 1)),
      jenis: JenisTransaksi.pengeluaran,
      kategori: 'Bahan Baku',
      jumlah: 2400000,
      keterangan: 'Biji kopi arabika & susu fresh',
    ),
    TransaksiModel(
      id: 4,
      unitId: 3,
      namaUnit: 'Toko Elektronik Digital',
      tanggal: DateTime.now().subtract(const Duration(days: 1)),
      jenis: JenisTransaksi.pemasukan,
      kategori: 'Aksesoris Handphone',
      jumlah: 4200000,
      keterangan: 'Penjualan langsung toko',
    ),
  ];

  String _filterJenis = 'Semua';

  List<TransaksiModel> get daftarTransaksi {
    if (_filterJenis == 'Pemasukan') {
      return _daftarTransaksi.where((t) => t.jenis == JenisTransaksi.pemasukan).toList();
    } else if (_filterJenis == 'Pengeluaran') {
      return _daftarTransaksi.where((t) => t.jenis == JenisTransaksi.pengeluaran).toList();
    }
    return _daftarTransaksi;
  }

  String get filterJenis => _filterJenis;

  void setFilterJenis(String jenis) {
    _filterJenis = jenis;
    notifyListeners();
  }

  void tambahTransaksi(TransaksiModel transaksi) {
    _daftarTransaksi.insert(0, transaksi);
    notifyListeners();
  }
}
