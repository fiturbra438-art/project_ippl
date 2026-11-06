import 'package:flutter/material.dart';
import '../models/gudang_model.dart';
import '../services/api_service.dart';

class GudangProvider extends ChangeNotifier {
  // Data gudang yang disinkronkan langsung dari PostgreSQL backend
  List<TransferStokModel> _daftarTransfer = [];
  List<StokOpnameModel> _daftarOpname = [];
  final List<MutasiStokModel> _daftarMutasi = [];
  bool _isLoading = false;
  String? _lastError;

  List<TransferStokModel> get daftarTransfer => _daftarTransfer;
  List<StokOpnameModel> get daftarOpname => _daftarOpname;
  List<MutasiStokModel> get daftarMutasi => _daftarMutasi;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  Future<void> fetchTransferFromApi({int? unitId}) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final endpoint = (unitId != null && unitId > 0) ? '/gudang/transfer?unit_id=$unitId' : '/gudang/transfer';
      final res = await ApiService.get(endpoint);
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final list = res['data'] as List;
        _daftarTransfer = list.map<TransferStokModel>((item) {
          final stStr = (item['status'] as String? ?? 'pending').toLowerCase();
          StatusTransfer stEnum = StatusTransfer.pending;
          if (stStr == 'diterima') stEnum = StatusTransfer.diterima;
          if (stStr == 'ditolak') stEnum = StatusTransfer.ditolak;

          return TransferStokModel(
            id: (item['id'] as num).toInt(),
            unitAsalId: (item['unit_asal_id'] as num).toInt(),
            namaUnitAsal: item['nama_unit_asal'] as String? ?? '',
            unitTujuanId: (item['unit_tujuan_id'] as num).toInt(),
            namaUnitTujuan: item['nama_unit_tujuan'] as String? ?? '',
            produkId: (item['produk_id'] as num).toInt(),
            namaProduk: item['nama_produk'] as String? ?? '',
            jumlah: (item['jumlah'] as num?)?.toInt() ?? 1,
            waktuKirim: DateTime.tryParse(item['waktu_kirim'] as String? ?? '') ?? DateTime.now(),
            status: stEnum,
          );
        }).toList();
      } else if (res != null && res['status'] == 'error') {
        _lastError = res['message'] as String?;
      }
    } catch (e) {
      debugPrint('GudangProvider.fetchTransferFromApi error: $e');
      _lastError = 'Gagal memuat data transfer stok: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchOpnameFromApi({int? unitId}) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final endpoint = (unitId != null && unitId > 0) ? '/gudang/opname?unit_id=$unitId' : '/gudang/opname';
      final res = await ApiService.get(endpoint);
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final list = res['data'] as List;
        _daftarOpname = list.map<StokOpnameModel>((item) {
          return StokOpnameModel(
            id: (item['id'] as num).toInt(),
            unitId: (item['unit_id'] as num).toInt(),
            namaUnit: item['nama_unit'] as String? ?? '',
            namaProduk: item['nama_produk'] as String? ?? '',
            stokSistem: (item['stok_sistem'] as num?)?.toInt() ?? 0,
            stokFisik: (item['stok_fisik'] as num?)?.toInt() ?? 0,
            alasan: item['alasan'] as String? ?? '',
            tanggal: DateTime.tryParse(item['tanggal'] as String? ?? '') ?? DateTime.now(),
          );
        }).toList();
      } else if (res != null && res['status'] == 'error') {
        _lastError = res['message'] as String?;
      }
    } catch (e) {
      debugPrint('GudangProvider.fetchOpnameFromApi error: $e');
      _lastError = 'Gagal memuat data stok opname: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> kirimTransferStok(TransferStokModel transfer) async {
    _lastError = null;
    try {
      final res = await ApiService.post('/gudang/transfer', {
        'unit_asal_id': transfer.unitAsalId,
        'unit_tujuan_id': transfer.unitTujuanId,
        'produk_id': transfer.produkId,
        'jumlah': transfer.jumlah,
      });
      if (res != null && res['status'] == 'success') {
        await fetchTransferFromApi(unitId: transfer.unitAsalId);
        return true;
      }
      _lastError = res?['message'] as String? ?? 'Gagal mengirim transfer stok.';
    } catch (e) {
      debugPrint('GudangProvider.kirimTransferStok error: $e');
      _lastError = 'Gagal mengirim transfer stok: $e';
    }

    notifyListeners();
    return false;
  }

  Future<bool> konfirmasiPenerimaan(int id) async {
    _lastError = null;
    try {
      final res = await ApiService.patch('/gudang/transfer/$id/status', {
        'status': 'diterima',
      });
      if (res != null && res['status'] == 'success') {
        final idx = _daftarTransfer.indexWhere((t) => t.id == id);
        if (idx != -1) {
          _daftarTransfer[idx].status = StatusTransfer.diterima;
          _daftarTransfer[idx].waktuTerima = DateTime.now();
          notifyListeners();
        }
        return true;
      }
      _lastError = res?['message'] as String? ?? 'Gagal mengonfirmasi penerimaan.';
    } catch (e) {
      debugPrint('GudangProvider.konfirmasiPenerimaan error: $e');
      _lastError = 'Gagal mengonfirmasi penerimaan: $e';
    }

    notifyListeners();
    return false;
  }

  Future<bool> tolakTransfer(int id) async {
    _lastError = null;
    try {
      final res = await ApiService.patch('/gudang/transfer/$id/status', {
        'status': 'ditolak',
      });
      if (res != null && res['status'] == 'success') {
        final idx = _daftarTransfer.indexWhere((t) => t.id == id);
        if (idx != -1) {
          _daftarTransfer[idx].status = StatusTransfer.ditolak;
          notifyListeners();
        }
        return true;
      }
      _lastError = res?['message'] as String? ?? 'Gagal menolak transfer.';
    } catch (e) {
      debugPrint('GudangProvider.tolakTransfer error: $e');
      _lastError = 'Gagal menolak transfer: $e';
    }

    notifyListeners();
    return false;
  }

  Future<bool> catatOpname(StokOpnameModel opname) async {
    _lastError = null;
    try {
      final res = await ApiService.post('/gudang/opname', {
        'unit_id': opname.unitId,
        'nama_produk': opname.namaProduk,
        'stok_fisik': opname.stokFisik,
        'alasan': opname.alasan,
      });
      if (res != null && res['status'] == 'success') {
        await fetchOpnameFromApi(unitId: opname.unitId);
        return true;
      }
      _lastError = res?['message'] as String? ?? 'Gagal mencatat stok opname.';
    } catch (e) {
      debugPrint('GudangProvider.catatOpname error: $e');
      _lastError = 'Gagal mencatat stok opname: $e';
    }

    notifyListeners();
    return false;
  }

  void catatMutasi(MutasiStokModel mutasi) {
    _daftarMutasi.insert(0, mutasi);
    notifyListeners();
  }
}
