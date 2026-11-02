import 'package:flutter/material.dart';
import '../models/produk.dart';
import '../services/api_service.dart';

enum ItemType { barang, rental, jasa }

class CartItem {
  final String id; // Unique cart line ID
  final ProdukModel? produk;
  String customNama;
  double customHarga;
  int kuantitas;
  ItemType tipe;
  int durasiSewa; // Contoh: durasi sewa (jam atau hari)
  String unitDurasi; // 'jam', 'hari', 'sesi'
  String catatan;
  double diskonNominal;

  CartItem({
    required this.id,
    this.produk,
    String? nama,
    double? harga,
    this.kuantitas = 1,
    this.tipe = ItemType.barang,
    this.durasiSewa = 1,
    this.unitDurasi = 'jam',
    this.catatan = '',
    this.diskonNominal = 0.0,
  })  : customNama = nama ?? produk?.nama ?? 'Item Khusus',
        customHarga = harga ?? produk?.hargaJual ?? 0.0;

  double get hargaEfektif {
    if (tipe == ItemType.rental) {
      return (customHarga * (durasiSewa > 0 ? durasiSewa : 1));
    }
    return customHarga;
  }

  double get subtotal {
    final raw = (hargaEfektif * kuantitas) - diskonNominal;
    return raw > 0 ? raw : 0.0;
  }
}

enum MetodeBayar { tunai, qris, transferBank, kartuDebit }
enum ModeOperasiKasir { retail, rental, jasa, fleksibel }

class PosProvider extends ChangeNotifier {
  final List<CartItem> _keranjang = [];
  double _diskonPersen = 0.0;
  MetodeBayar _metodeBayar = MetodeBayar.qris;
  ModeOperasiKasir _modeOperasi = ModeOperasiKasir.fleksibel;
  String _namaPelanggan = '';
  String _catatanTransaksi = '';
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

  // Active Rental & Service Orders
  List<Map<String, dynamic>> _activeOrders = [];
  bool _isLoadingOrders = false;

  List<CartItem> get keranjang => _keranjang;
  double get diskonPersen => _diskonPersen;
  MetodeBayar get metodeBayar => _metodeBayar;
  ModeOperasiKasir get modeOperasi => _modeOperasi;
  String get namaPelanggan => _namaPelanggan;
  String get catatanTransaksi => _catatanTransaksi;
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
  List<Map<String, dynamic>> get activeOrders => _activeOrders;
  bool get isLoadingOrders => _isLoadingOrders;

  // 1a. Load Pesanan Rental & Jasa yang sedang aktif
  Future<void> loadActiveOrders(int unitId) async {
    _isLoadingOrders = true;
    notifyListeners();
    try {
      final res = await ApiService.get('/pos/orders/active?unit_id=$unitId');
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final list = res['data'] as List;
        _activeOrders = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _activeOrders = [];
      }
    } catch (_) {
      _activeOrders = [];
    }
    _isLoadingOrders = false;
    notifyListeners();
  }

  // 1b. Pengembalian Rental (Return)
  Future<bool> returnRentalOrder(int orderId, {double penalty = 0.0, String? notes}) async {
    try {
      final res = await ApiService.post('/pos/rental/return', {
        'order_id': orderId,
        'penalty_fee': penalty,
        'notes': notes,
      });
      if (res != null && res['status'] == 'success') {
        if (_activeUnitId > 0) {
          await loadActiveOrders(_activeUnitId);
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  // 1c. Update Status Layanan Jasa (queued, in_progress, ready, completed)
  Future<bool> updateServiceOrderStatus(int orderId, String newStatus, {String? staff, String? notes}) async {
    try {
      final res = await ApiService.patch('/pos/service/status', {
        'order_id': orderId,
        'status': newStatus,
        'assigned_staff': staff,
        'notes': notes,
      });
      if (res != null && res['status'] == 'success') {
        if (_activeUnitId > 0) {
          await loadActiveOrders(_activeUnitId);
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  void setModeOperasi(ModeOperasiKasir mode) {
    _modeOperasi = mode;
    notifyListeners();
  }

  void setPelanggan(String nama) {
    _namaPelanggan = nama;
    notifyListeners();
  }

  void setCatatanTransaksi(String catatan) {
    _catatanTransaksi = catatan;
    notifyListeners();
  }

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

    // Kirim struktur item lengkap (id produk opsional, nama custom, tipe, tarif sewa/jasa, durasi sewa, catatan)
    final itemsPayload = _keranjang.map((c) {
      return {
        'produk_id': c.produk?.id,
        'nama': c.customNama,
        'tipe': c.tipe.name,
        'jumlah': c.kuantitas,
        'harga_satuan': c.hargaEfektif,
        'durasi': c.durasiSewa,
        'unit_durasi': c.unitDurasi,
        'catatan': c.catatan,
      };
    }).toList();

    final detailCatatan = StringBuffer();
    if (_namaPelanggan.trim().isNotEmpty) {
      detailCatatan.write('Pelanggan: ${_namaPelanggan.trim()} | ');
    }
    if (_modeOperasi != ModeOperasiKasir.fleksibel) {
      detailCatatan.write('Mode: ${_modeOperasi.name.toUpperCase()} | ');
    }
    if (_catatanTransaksi.trim().isNotEmpty) {
      detailCatatan.write('Catatan: ${_catatanTransaksi.trim()} | ');
    }

    final customItems = _keranjang.where((c) => c.produk == null || c.tipe != ItemType.barang || c.catatan.isNotEmpty);
    if (customItems.isNotEmpty) {
      detailCatatan.write('Rincian: ');
      for (final item in customItems) {
        detailCatatan.write(
          '[${item.tipe.name.toUpperCase()}] ${item.customNama} '
          '(${item.tipe == ItemType.rental ? '${item.durasiSewa} ${item.unitDurasi}, ' : ''}'
          'Rp ${item.hargaEfektif.toInt()} x ${item.kuantitas}'
          '${item.catatan.isNotEmpty ? ', ket: ${item.catatan}' : ''}); ',
        );
      }
    }

    final finalKeterangan = (keterangan ?? '') +
        (detailCatatan.isNotEmpty ? ' [${detailCatatan.toString().trim()}]' : '');

    try {
      final res = await ApiService.post('/pos/checkout', {
        'unit_id': unitId,
        'items': itemsPayload,
        'metode_pembayaran': metodeBayarStr,
        'keterangan': finalKeterangan.trim(),
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

  void tambahKeKeranjang(ProdukModel produk, {ItemType tipe = ItemType.barang, int durasi = 1, String unitDurasi = 'jam'}) {
    final cartItemId = 'prod_${produk.id}_${tipe.name}';
    final idx = _keranjang.indexWhere((item) => item.id == cartItemId);
    if (idx != -1) {
      _keranjang[idx].kuantitas++;
    } else {
      _keranjang.add(CartItem(
        id: cartItemId,
        produk: produk,
        nama: produk.nama,
        harga: produk.hargaJual,
        kuantitas: 1,
        tipe: tipe,
        durasiSewa: durasi,
        unitDurasi: unitDurasi,
      ));
    }
    notifyListeners();
  }

  // Tambah item custom langsung (misal: jasa servis, sewa lapangan/alat, atau item non-katalog)
  void tambahItemKustom({
    required String nama,
    required double harga,
    int kuantitas = 1,
    ItemType tipe = ItemType.barang,
    int durasi = 1,
    String unitDurasi = 'jam',
    String catatan = '',
  }) {
    final cartItemId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    _keranjang.add(CartItem(
      id: cartItemId,
      nama: nama,
      harga: harga,
      kuantitas: kuantitas,
      tipe: tipe,
      durasiSewa: durasi,
      unitDurasi: unitDurasi,
      catatan: catatan,
    ));
    notifyListeners();
  }

  void updateCartItem(
    String cartId, {
    String? nama,
    double? harga,
    int? kuantitas,
    ItemType? tipe,
    int? durasiSewa,
    String? unitDurasi,
    String? catatan,
    double? diskonNominal,
  }) {
    final idx = _keranjang.indexWhere((item) => item.id == cartId);
    if (idx != -1) {
      if (nama != null) _keranjang[idx].customNama = nama;
      if (harga != null) _keranjang[idx].customHarga = harga;
      if (kuantitas != null) _keranjang[idx].kuantitas = kuantitas;
      if (tipe != null) _keranjang[idx].tipe = tipe;
      if (durasiSewa != null) _keranjang[idx].durasiSewa = durasiSewa;
      if (unitDurasi != null) _keranjang[idx].unitDurasi = unitDurasi;
      if (catatan != null) _keranjang[idx].catatan = catatan;
      if (diskonNominal != null) _keranjang[idx].diskonNominal = diskonNominal;

      if (_keranjang[idx].kuantitas <= 0) {
        _keranjang.removeAt(idx);
      }
      notifyListeners();
    }
  }

  void hapusItemKeranjang(String cartId) {
    _keranjang.removeWhere((item) => item.id == cartId);
    notifyListeners();
  }

  void ubahKuantitasById(String cartId, int delta) {
    final idx = _keranjang.indexWhere((item) => item.id == cartId);
    if (idx != -1) {
      _keranjang[idx].kuantitas += delta;
      if (_keranjang[idx].kuantitas <= 0) {
        _keranjang.removeAt(idx);
      }
      notifyListeners();
    }
  }

  void ubahKuantitas(int produkId, int delta) {
    final idx = _keranjang.indexWhere((item) => item.produk?.id == produkId);
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
    _namaPelanggan = '';
    _catatanTransaksi = '';
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
