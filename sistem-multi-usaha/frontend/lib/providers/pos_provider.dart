import 'package:flutter/material.dart';
import '../models/produk.dart';

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

  // Tutup Shift Data
  double _modalAwal = 500000; // Rp 500.000 kas awal di laci
  double _totalPenjualanShift = 1850000;
  bool _shiftIsOpen = true;

  List<CartItem> get keranjang => _keranjang;
  double get diskonPersen => _diskonPersen;
  MetodeBayar get metodeBayar => _metodeBayar;
  bool get isOfflineMode => _isOfflineMode;
  int get offlineQueueCount => _offlineQueueCount;
  double get modalAwal => _modalAwal;
  double get totalPenjualanShift => _totalPenjualanShift;
  bool get shiftIsOpen => _shiftIsOpen;

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
    _totalPenjualanShift += grandTotal;
    _keranjang.clear();
    _diskonPersen = 0;
    notifyListeners();
  }

  void tutupShiftKasir(double uangFisikDiLaci) {
    _shiftIsOpen = false;
    notifyListeners();
  }

  void bukaShiftBaru(double modal) {
    _modalAwal = modal;
    _totalPenjualanShift = 0;
    _shiftIsOpen = true;
    notifyListeners();
  }
}
