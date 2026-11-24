import 'package:flutter/material.dart';
import '../models/transaksi.dart';
import '../services/api_service.dart';

class TransaksiProvider extends ChangeNotifier {
  // Data transaksi yang disinkronkan langsung dari PostgreSQL backend
  List<TransaksiModel> _daftarTransaksi = [];
  bool _isLoading = false;
  String? _lastError;

  String _filterJenis = 'Semua';

  List<TransaksiModel> get daftarTransaksi {
    if (_filterJenis == 'Pemasukan') {
      return _daftarTransaksi.where((t) => t.jenis == JenisTransaksi.pemasukan).toList();
    } else if (_filterJenis == 'Pengeluaran') {
      return _daftarTransaksi.where((t) => t.jenis == JenisTransaksi.pengeluaran).toList();
    }
    return _daftarTransaksi;
  }

  bool get isLoading => _isLoading;
  String get filterJenis => _filterJenis;
  String? get lastError => _lastError;

  Future<void> fetchTransaksiFromApi({int? unitId}) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final endpoint = (unitId != null && unitId > 0) ? '/transaksi?unit_id=$unitId' : '/transaksi';
      final res = await ApiService.get(endpoint);
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final paginated = res['data'] as Map<String, dynamic>;
        final list = paginated['items'] as List? ?? [];
        _daftarTransaksi = list.map<TransaksiModel>((item) {
          final jenisStr = (item['jenis'] as String? ?? 'pemasukan').toLowerCase();
          final tglStr = item['tanggal'] as String? ?? '';
          return TransaksiModel(
            id: (item['id'] as num).toInt(),
            unitId: (item['unit_id'] as num).toInt(),
            namaUnit: item['nama_unit'] as String? ?? 'Unit Usaha',
            tanggal: DateTime.tryParse(tglStr) ?? DateTime.now(),
            jenis: jenisStr == 'pengeluaran' ? JenisTransaksi.pengeluaran : JenisTransaksi.pemasukan,
            kategori: item['kategori'] as String? ?? 'Umum',
            jumlah: (item['jumlah'] as num?)?.toDouble() ?? 0.0,
            keterangan: item['keterangan'] as String? ?? '',
          );
        }).toList();
      } else if (res != null && res['status'] == 'error') {
        _lastError = res['message'] as String?;
      }
    } catch (e) {
      debugPrint('TransaksiProvider.fetchTransaksiFromApi error: $e');
      _lastError = 'Gagal memuat transaksi: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  void setFilterJenis(String jenis) {
    _filterJenis = jenis;
    notifyListeners();
  }

  TransaksiDetailModel? _detail;
  TransaksiDetailModel? get detail => _detail;

  TransaksiDetailModel _parseDetail(Map<String, dynamic> data) {
    final items = (data['items'] as List? ?? []).map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      return TransaksiItemDetail(
        id: (m['id'] as num).toInt(),
        productId: (m['product_id'] as num?)?.toInt(),
        itemName: m['item_name'] as String? ?? '-',
        itemType: m['item_type'] as String? ?? 'barang',
        qty: (m['qty'] as num?)?.toInt() ?? 0,
        hargaSatuan: (m['harga_satuan'] as num?)?.toDouble() ?? 0,
        subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
        refundedQty: (m['refunded_qty'] as num?)?.toInt() ?? 0,
        refundableQty: (m['refundable_qty'] as num?)?.toInt() ?? 0,
      );
    }).toList();

    final refunds = (data['refunds'] as List? ?? []).map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final refundItems = (m['items'] as List? ?? []).map((riRaw) {
        final ri = Map<String, dynamic>.from(riRaw as Map);
        return RefundItemModel(
          transactionItemId: (ri['transaction_item_id'] as num?)?.toInt() ?? 0,
          productId: (ri['product_id'] as num?)?.toInt(),
          itemName: ri['item_name'] as String? ?? '-',
          itemType: ri['item_type'] as String? ?? 'barang',
          qty: (ri['qty'] as num?)?.toInt() ?? 0,
          jumlah: (ri['jumlah'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
      return RefundModel(
        id: (m['id'] as num?)?.toInt() ?? 0,
        transactionId: (m['transaction_id'] as num?)?.toInt() ?? 0,
        unitId: (m['unit_id'] as num?)?.toInt() ?? 0,
        jenis: m['jenis'] as String? ?? 'refund',
        alasan: m['alasan'] as String? ?? '',
        jumlah: (m['jumlah'] as num?)?.toDouble() ?? 0,
        aktor: m['aktor'] as String? ?? '-',
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
        items: refundItems,
      );
    }).toList();

    return TransaksiDetailModel(
      id: (data['id'] as num?)?.toInt() ?? 0,
      unitId: (data['unit_id'] as num?)?.toInt() ?? 0,
      namaUnit: data['nama_unit'] as String? ?? 'Unit Usaha',
      tanggal: DateTime.tryParse(data['tanggal']?.toString() ?? '') ?? DateTime.now(),
      total: (data['total'] as num?)?.toDouble() ?? 0,
      metodeBayar: data['metode_bayar'] as String? ?? '-',
      status: data['status'] as String? ?? '-',
      customerName: data['customer_name'] as String?,
      notes: data['notes'] as String?,
      items: items,
      refunds: refunds,
      refundedTotal: (data['refunded_total'] as num?)?.toDouble() ?? 0,
      refundableTotal: (data['refundable_total'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<TransaksiDetailModel?> fetchTransaksiDetail(int id) async {
    _lastError = null;
    try {
      final res = await ApiService.get('/transaksi/$id');
      if (res != null && res['status'] == 'success' && res['data'] is Map) {
        _detail = _parseDetail(Map<String, dynamic>.from(res['data'] as Map));
        notifyListeners();
        return _detail;
      }
      _lastError = res?['message'] as String? ?? 'Gagal memuat detail transaksi.';
    } catch (e) {
      debugPrint('TransaksiProvider.fetchTransaksiDetail error: $e');
      _lastError = 'Gagal memuat detail transaksi: $e';
    }
    notifyListeners();
    return null;
  }

  Future<bool> ajukanRefund({
    required int id,
    required String alasan,
    bool voidMode = false,
    Map<int, int> items = const {},
    String? idempotencyKey,
  }) async {
    _lastError = null;
    try {
      final res = await ApiService.post('/transaksi/$id/refund', {
        'alasan': alasan,
        'void': voidMode,
        'idempotency_key': idempotencyKey ?? '${id}_${DateTime.now().microsecondsSinceEpoch}',
        'items': items.entries
            .map((entry) => {'transaction_item_id': entry.key, 'qty': entry.value})
            .toList(),
      });
      if (res != null && res['status'] == 'success') {
        await fetchTransaksiDetail(id);
        final unitId = _detail?.unitId;
        await fetchTransaksiFromApi(unitId: unitId);
        return true;
      }
      _lastError = res?['message'] as String? ?? 'Gagal memproses refund.';
    } catch (e) {
      debugPrint('TransaksiProvider.ajukanRefund error: $e');
      _lastError = 'Gagal memproses refund: $e';
    }
    notifyListeners();
    return false;
  }

  Future<bool> catatTransaksiManual({
    required int unitId,
    required JenisTransaksi jenis,
    required String kategori,
    required double jumlah,
  }) async {
    _lastError = null;
    try {
      final response = await ApiService.post('/transaksi', {
        'unit_id': unitId,
        'jenis': jenis.name,
        'kategori': kategori,
        'jumlah': jumlah,
        'keterangan': kategori,
      });
      if (response != null && response['status'] == 'success') {
        await fetchTransaksiFromApi(unitId: unitId);
        return true;
      }
      _lastError = response?['message'] as String? ?? 'Gagal menyimpan transaksi.';
    } catch (error) {
      debugPrint('TransaksiProvider.catatTransaksiManual error: $error');
      _lastError = 'Gagal menyimpan transaksi: $error';
    }
    notifyListeners();
    return false;
  }
}
