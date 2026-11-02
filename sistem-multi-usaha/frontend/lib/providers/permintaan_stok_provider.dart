import 'package:flutter/material.dart';
import '../models/permintaan_stok_model.dart';
import '../services/api_service.dart';

class PermintaanStokProvider extends ChangeNotifier {
  // Data permintaan stok yang disinkronkan langsung dari PostgreSQL backend
  List<PermintaanStokModel> _daftarPermintaan = [];
  bool _isLoading = false;

  List<PermintaanStokModel> get daftarPermintaan => _daftarPermintaan;
  bool get isLoading => _isLoading;

  Future<void> fetchPermintaanFromApi({int? unitId}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final endpoint = (unitId != null && unitId > 0) ? '/gudang/permintaan?unit_id=$unitId' : '/gudang/permintaan';
      final res = await ApiService.get(endpoint);
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final list = res['data'] as List;
        _daftarPermintaan = list.map<PermintaanStokModel>((item) {
          final stStr = (item['status'] as String? ?? 'pending').toLowerCase();
          StatusPermintaanStok stEnum = StatusPermintaanStok.pending;
          if (stStr == 'disetujui') stEnum = StatusPermintaanStok.disetujui;
          if (stStr == 'ditolak') stEnum = StatusPermintaanStok.ditolak;
          if (stStr == 'selesai') stEnum = StatusPermintaanStok.selesai;

          return PermintaanStokModel(
            id: (item['id'] as num).toInt(),
            unitId: (item['unit_id'] as num).toInt(),
            namaUnit: item['nama_unit'] as String? ?? 'Unit Usaha',
            pemohon: item['pemohon'] as String? ?? 'Admin',
            namaProduk: item['nama_produk'] as String? ?? '',
            jumlahDiminta: (item['jumlah_diminta'] as num?)?.toInt() ?? 1,
            alasan: item['alasan'] as String? ?? '',
            waktuPengajuan: DateTime.tryParse(item['waktu_pengajuan'] as String? ?? '') ?? DateTime.now(),
            status: stEnum,
          );
        }).toList();
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> ajukanPermintaan(PermintaanStokModel permintaan) async {
    try {
      final res = await ApiService.post('/gudang/permintaan', {
        'unit_id': permintaan.unitId,
        'nama_produk': permintaan.namaProduk,
        'jumlah_diminta': permintaan.jumlahDiminta,
        'alasan': permintaan.alasan,
      });
      if (res != null && res['status'] == 'success') {
        await fetchPermintaanFromApi(unitId: permintaan.unitId);
        return true;
      }
    } catch (_) {}

    _daftarPermintaan.insert(0, permintaan);
    notifyListeners();
    return true;
  }

  Future<bool> setujuiPermintaan(int id) async {
    try {
      final res = await ApiService.patch('/gudang/permintaan/$id/status', {
        'status': 'disetujui',
      });
      if (res != null && res['status'] == 'success') {
        final idx = _daftarPermintaan.indexWhere((p) => p.id == id);
        if (idx != -1) {
          _daftarPermintaan[idx].status = StatusPermintaanStok.disetujui;
          notifyListeners();
        }
        return true;
      }
    } catch (_) {}

    final idx = _daftarPermintaan.indexWhere((p) => p.id == id);
    if (idx != -1) {
      _daftarPermintaan[idx].status = StatusPermintaanStok.disetujui;
      notifyListeners();
    }
    return false;
  }

  Future<bool> tolakPermintaan(int id) async {
    try {
      final res = await ApiService.patch('/gudang/permintaan/$id/status', {
        'status': 'ditolak',
      });
      if (res != null && res['status'] == 'success') {
        final idx = _daftarPermintaan.indexWhere((p) => p.id == id);
        if (idx != -1) {
          _daftarPermintaan[idx].status = StatusPermintaanStok.ditolak;
          notifyListeners();
        }
        return true;
      }
    } catch (_) {}

    final idx = _daftarPermintaan.indexWhere((p) => p.id == id);
    if (idx != -1) {
      _daftarPermintaan[idx].status = StatusPermintaanStok.ditolak;
      notifyListeners();
    }
    return false;
  }
}
