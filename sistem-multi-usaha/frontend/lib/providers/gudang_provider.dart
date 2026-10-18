import 'package:flutter/material.dart';
import '../models/gudang_model.dart';

class GudangProvider extends ChangeNotifier {
  // Data bersih awal (0 transfer, 0 opname, 0 mutasi)
  final List<TransferStokModel> _daftarTransfer = [];
  final List<StokOpnameModel> _daftarOpname = [];
  final List<MutasiStokModel> _daftarMutasi = [];

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
