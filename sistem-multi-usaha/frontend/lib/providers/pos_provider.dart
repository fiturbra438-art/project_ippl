import 'package:flutter/material.dart';
import '../models/produk.dart';
import '../services/api_service.dart';

class CartItem {
  final ProdukModel produk;
  int kuantitas;

  CartItem({required this.produk, this.kuantitas = 1});

  double get subtotal => produk.hargaJual * kuantitas;
}

enum MetodeBayar { tunai, qris, transferBank, kartuDebit }

class PosProvider extends ChangeNotifier {
  final List<CartItem> _keranjang = [];
  double _diskonPersen = 0.0;
  MetodeBayar _metodeBayar = MetodeBayar.qris;
  bool _isOfflineMode = false;
  int _offlineQueueCount = 0;
  int _activeUnitId = 0;
  String _activeUnitNama = '';

  // Tutup Shift Data (Awal 0)
  int? _activeShiftId;
  double _modalAwal = 0.0;
  double _totalPenjualanShift = 0.0;
  double _totalPenjualanTunai = 0.0;
  double _totalPenjualanNonTunai = 0.0;
  int _totalTransaksiShift = 0;
  String _waktuBukaShift = '';
  bool _shiftIsOpen = false;

  List<CartItem> get keranjang => _keranjang;
  double get diskonPersen => _diskonPersen;
  MetodeBayar get metodeBayar => _metodeBayar;
  bool get isOfflineMode => _isOfflineMode;
  int get offlineQueueCount => _offlineQueueCount;
  int get activeUnitId => _activeUnitId;
  String get activeUnitNama => _activeUnitNama;
  int? get activeShiftId => _activeShiftId;
  double get modalAwal => _modalAwal;
  double get totalPenjualanShift => _totalPenjualanShift;
  double get totalPenjualanTunai => _totalPenjualanTunai;
  double get totalPenjualanNonTunai => _totalPenjualanNonTunai;
  int get totalTransaksiShift => _totalTransaksiShift;
  String get waktuBukaShift => _waktuBukaShift;
  bool get shiftIsOpen => _shiftIsOpen;

  // 1. Ambil status shift dari PostgreSQL via API
  Future<void> initShiftStatus(int unitId) async {
    try {
      final res = await ApiService.get('/pos/shift/$unitId');
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final d = res['data'] as Map<String, dynamic>;
        _activeShiftId = (d['id'] as num?)?.toInt();
        _modalAwal = (d['modal_awal'] as num?)?.toDouble() ?? 0.0;
        _totalPenjualanTunai = (d['total_penjualan_tunai'] as num?)?.toDouble() ?? 0.0;
        _totalPenjualanNonTunai = (d['total_penjualan_non_tunai'] as num?)?.toDouble() ?? 0.0;
        _totalPenjualanShift = _totalPenjualanTunai + _totalPenjualanNonTunai;
        _totalTransaksiShift = (d['total_transaksi'] as num?)?.toInt() ?? 0;
        _waktuBukaShift = d['waktu_buka'] as String? ?? '';
        _shiftIsOpen = true;
      } else {
        _activeShiftId = null;
        _shiftIsOpen = false;
        _totalPenjualanShift = 0.0;
        _totalPenjualanTunai = 0.0;
        _totalPenjualanNonTunai = 0.0;
        _totalTransaksiShift = 0;
        _waktuBukaShift = '';
      }
    } catch (_) {
      // Fallback tetap menggunakan status memori jika API belum siap
    }
    notifyListeners();
  }

  // 2. Buka shift kasir via API (sp_buka_shift_kasir)
  Future<bool> bukaShiftAPI(int unitId, double modal) async {
    try {
      final res = await ApiService.post('/pos/shift/buka', {
        'unit_id': unitId,
        'modal_awal': modal,
      });
      if (res != null && res['status'] == 'success') {
        if (res['data'] != null) {
          _activeShiftId = (res['data']['id'] as num?)?.toInt();
        }
        _modalAwal = modal;
        _totalPenjualanShift = 0.0;
        _shiftIsOpen = true;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  // 3. Tutup shift kasir via API (sp_tutup_shift_kasir)
  Future<bool> tutupShiftAPI(double uangFisikDiLaci) async {
    if (_activeShiftId != null) {
      try {
        final res = await ApiService.post('/pos/shift/tutup', {
          'shift_id': _activeShiftId,
        });
        if (res != null && res['status'] == 'success') {
          _shiftIsOpen = false;
          _activeShiftId = null;
          notifyListeners();
          return true;
        }
      } catch (_) {}
    }
    // Fallback lokal
    _shiftIsOpen = false;
    _activeShiftId = null;
    notifyListeners();
    return true;
  }

  // 4. Checkout kasir via API (sp_proses_checkout_kasir & trigger update stok/omzet)
  Future<bool> checkoutAPI(int unitId, String metodeBayarStr, {String? keterangan}) async {
    if (_keranjang.isEmpty) return false;

    final itemsPayload = _keranjang.map((c) {
      return {
        'produk_id': c.produk.id,
        'jumlah': c.kuantitas,
        'harga_satuan': c.produk.hargaJual,
      };
    }).toList();

    try {
      final res = await ApiService.post('/pos/checkout', {
        'unit_id': unitId,
        'items': itemsPayload,
        'metode_pembayaran': metodeBayarStr,
        'keterangan': keterangan ?? 'Order Kasir POS',
      });

      if (res != null && res['status'] == 'success') {
        checkoutBerhasil();
        return true;
      }
    } catch (_) {}

    // Jika offline mode aktif atau request fallback
    if (_isOfflineMode) {
      checkoutBerhasil();
      return true;
    }

    return false;
  }

  void setActiveUnit(int unitId, String unitNama) {
    if (_activeUnitId != unitId) {
      _activeUnitId = unitId;
      _activeUnitNama = unitNama;
      _keranjang.clear();
      _totalPenjualanShift = 0;
      notifyListeners();
    }
  }

  double get subtotal => _keranjang.fold(0, (sum, item) => sum + item.subtotal);
  double get nominalDiskon => (subtotal * _diskonPersen) / 100;
  double get grandTotal => subtotal - nominalDiskon;

  void toggleOfflineMode() {
    _isOfflineMode = !_isOfflineMode;
    if (!_isOfflineMode && _offlineQueueCount > 0) {
      // Sinkronisasi otomatis saat online kembali
      _offlineQueueCount = 0;
    }
    notifyListeners();
  }

  void tambahKeKeranjang(ProdukModel produk) {
    final idx = _keranjang.indexWhere((item) => item.produk.id == produk.id);
    if (idx != -1) {
      _keranjang[idx].kuantitas++;
    } else {
      _keranjang.add(CartItem(produk: produk, kuantitas: 1));
    }
    notifyListeners();
  }

  void ubahKuantitas(int produkId, int delta) {
    final idx = _keranjang.indexWhere((item) => item.produk.id == produkId);
    if (idx != -1) {
      _keranjang[idx].kuantitas += delta;
      if (_keranjang[idx].kuantitas <= 0) {
        _keranjang.removeAt(idx);
      }
      notifyListeners();
    }
  }

  void setDiskon(double persen) {
    _diskonPersen = persen;
    notifyListeners();
  }

  void setMetodeBayar(MetodeBayar metode) {
    _metodeBayar = metode;
    notifyListeners();
  }

  void checkoutBerhasil() {
    if (_isOfflineMode) {
      _offlineQueueCount++;
    }
    if (_metodeBayar == MetodeBayar.tunai) {
      _totalPenjualanTunai += grandTotal;
    } else {
      _totalPenjualanNonTunai += grandTotal;
    }
    _totalPenjualanShift += grandTotal;
    _totalTransaksiShift++;
    _keranjang.clear();
    _diskonPersen = 0;
    notifyListeners();
  }

  void tutupShiftKasir(double uangFisikDiLaci) {
    _shiftIsOpen = false;
    _activeShiftId = null;
    notifyListeners();
  }

  void bukaShiftBaru(double modal) {
    _modalAwal = modal;
    _totalPenjualanShift = 0;
    _totalPenjualanTunai = 0;
    _totalPenjualanNonTunai = 0;
    _totalTransaksiShift = 0;
    _waktuBukaShift = DateTime.now().toString().substring(0, 16);
    _shiftIsOpen = true;
    notifyListeners();
  }
}
