import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/ai_models.dart';
import '../services/api_service.dart';

class AiUnitOption {
  final int id;
  final String nama;
  final String kategori;

  AiUnitOption({required this.id, required this.nama, required this.kategori});
}

class AiSuiteProvider extends ChangeNotifier {
  int _horizonHari = 7;
  int _selectedProdukId = 1;
  int _selectedUnitId = 0;
  String _selectedUnitNama = '';

  final List<PermintaanPrediksiModel> _prediksi7Hari = [];
  final List<PermintaanPrediksiModel> _prediksi30Hari = [];

  final List<RealokasiStokAiModel> _daftarRealokasi = [];
  final List<AnomaliModel> _daftarAnomali = [];
  final List<AiUnitOption> _units = [];

  int _unitSumberSurplus = 0;
  int _unitPenerimaModal = 0;
  String _unitSumberNama = '-';
  String _unitTujuanNama = '-';
  String _unitTujuanKategori = '';
  double _surplusKasSumber = 0;
  double _persenAlokasiSurplus = 30.0;

  bool _isLoading = false;
  String? _lastError;

  int get horizonHari => _horizonHari;
  int get selectedProdukId => _selectedProdukId;
  int get selectedUnitId => _selectedUnitId;
  String get selectedUnitNama => _selectedUnitNama;
  List<AiUnitOption> get units => _units;

  List<PermintaanPrediksiModel> get listPrediksi =>
      _horizonHari == 7 ? _prediksi7Hari : _prediksi30Hari;
  List<PermintaanPrediksiModel> get prediksiList => listPrediksi;
  List<RealokasiStokAiModel> get daftarRealokasi => _daftarRealokasi;
  List<AnomaliModel> get daftarAnomali => _daftarAnomali;

  int get unitSumberSurplus => _unitSumberSurplus;
  int get unitPenerimaModal => _unitPenerimaModal;
  String get unitSumberNama => _unitSumberNama;
  String get unitTujuanNama => _unitTujuanNama;
  String get unitTujuanKategori => _unitTujuanKategori;
  double get persenAlokasiSurplus => _persenAlokasiSurplus;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  double get nominalSurplusKasLaundry => _surplusKasSumber;
  double get modalDialokasikan =>
      (_surplusKasSumber * _persenAlokasiSurplus) / 100;
  double get proyeksiKenaikanOmzetPenerima => modalDialokasikan * 1.85;
  double get proyeksiPertumbuhanPersenPenerima =>
      4.5 + (_persenAlokasiSurplus * 0.45);

  Future<void> fetchAll() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    await _fetchPortfolio();
    await Future.wait([fetchReallocation(), fetchAnomali()]);
    await fetchPrediksi();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _fetchPortfolio() async {
    try {
      final res = await ApiService.get('/ai/portfolio');
      if (res == null || res['status'] != 'success' || res['data'] == null) {
        _lastError =
            res?['message'] as String? ?? 'Gagal memuat portofolio AI.';
        return;
      }

      final data = Map<String, dynamic>.from(res['data'] as Map);
      final items = (data['items'] as List?) ?? [];
      _units
        ..clear()
        ..addAll(items.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return AiUnitOption(
            id: (map['id'] as num).toInt(),
            nama: map['nama_usaha'] as String? ?? 'Unit Usaha',
            kategori: map['kategori'] as String? ?? 'Star',
          );
        }));

      if (_units.isEmpty) return;

      final source = _units.firstWhere(
        (unit) => unit.kategori == 'Cash Cow',
        orElse: () => _units.first,
      );
      final target = _units.firstWhere(
        (unit) => unit.kategori == 'Question Mark',
        orElse: () => _units.firstWhere(
          (unit) => unit.id != source.id,
          orElse: () => _units.first,
        ),
      );

      _unitSumberSurplus = source.id;
      _unitPenerimaModal = target.id;
      _unitSumberNama = source.nama;
      _unitTujuanNama = target.nama;
      _unitTujuanKategori = target.kategori;

      final sourceItem = items.firstWhere(
        (item) => (item as Map)['id'] == source.id,
        orElse: () => items.first,
      );
      _surplusKasSumber =
          ((sourceItem as Map)['arus_kas'] as num?)?.toDouble() ?? 0;

      _selectedUnitId = _units.first.id;
      _selectedUnitNama = _units.first.nama;

      await _fetchWhatIf();
      notifyListeners();
    } catch (e) {
      debugPrint('AiSuiteProvider._fetchPortfolio error: $e');
      _lastError = 'Gagal memuat portofolio AI: $e';
    }
  }

  Future<void> _fetchWhatIf() async {
    if (_unitSumberSurplus == 0 || _unitPenerimaModal == 0) return;
    try {
      final res = await ApiService.post('/ai/what-if', {
        'unit_sumber_id': _unitSumberSurplus,
        'unit_tujuan_id': _unitPenerimaModal,
        'persen_alokasi': _persenAlokasiSurplus,
      });
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        _unitSumberNama = data['unit_sumber'] as String? ?? _unitSumberNama;
        _unitTujuanNama = data['unit_tujuan'] as String? ?? _unitTujuanNama;
        _surplusKasSumber = (data['surplus_kas_sumber'] as num?)?.toDouble() ??
            _surplusKasSumber;
      }
    } catch (e) {
      debugPrint('AiSuiteProvider._fetchWhatIf error: $e');
    }
  }

  Future<void> fetchPrediksi() async {
    if (_selectedUnitId == 0) return;
    try {
      final res = await ApiService.get(
        '/ai/forecast/$_selectedUnitId/products?horizon=$_horizonHari',
      );
      if (res == null || res['status'] != 'success' || res['data'] == null) {
        _lastError = res?['message'] as String? ?? 'Gagal memuat prediksi.';
        notifyListeners();
        return;
      }

      final data = Map<String, dynamic>.from(res['data'] as Map);
      final items = (data['items'] as List?) ?? [];
      if (items.isEmpty) {
        _prediksi7Hari.clear();
        _prediksi30Hari.clear();
        notifyListeners();
        return;
      }

      final selectedItem = items.firstWhere(
        (item) => (item as Map)['product_id'] == _selectedProdukId,
        orElse: () => items.first,
      );
      final itemMap = Map<String, dynamic>.from(selectedItem as Map);
      _selectedProdukId =
          (itemMap['product_id'] as num?)?.toInt() ?? _selectedProdukId;

      final proyeksi = (itemMap['proyeksi'] as List?) ?? [];
      final parsed = proyeksi.map((point) {
        final map = Map<String, dynamic>.from(point as Map);
        return PermintaanPrediksiModel(
          periode: _periodeLabel(map['tanggal']),
          prediksi: (map['prediksi_qty'] as num?)?.toDouble() ?? 0,
          statusRisiko: map['status_risiko'] as String? ?? 'NORMAL',
        );
      }).toList();

      if (_horizonHari == 7) {
        _prediksi7Hari
          ..clear()
          ..addAll(parsed);
      } else {
        _prediksi30Hari
          ..clear()
          ..addAll(parsed);
      }
      _lastError = null;
      notifyListeners();
    } catch (e) {
      debugPrint('AiSuiteProvider.fetchPrediksi error: $e');
      _lastError = 'Gagal memuat prediksi: $e';
      notifyListeners();
    }
  }

  Future<void> fetchReallocation() async {
    try {
      final res = await ApiService.get('/ai/reallocation');
      if (res == null || res['status'] != 'success' || res['data'] == null) {
        return;
      }
      final list = res['data'] as List;
      _daftarRealokasi
        ..clear()
        ..addAll(list.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return RealokasiStokAiModel(
            id: (map['id'] as num).toInt(),
            namaProduk: map['nama_produk'] as String? ?? 'Produk',
            unitSumber: map['unit_sumber'] as String? ?? '-',
            unitTujuan: map['unit_tujuan'] as String? ?? '-',
            jumlahPindah: (map['jumlah_pindah'] as num?)?.toInt() ?? 0,
            alasanAi: map['alasan_ai'] as String? ?? '',
            estimasiHematBiaya:
                (map['estimasi_hemat_biaya'] as num?)?.toDouble() ?? 0,
          );
        }));
      notifyListeners();
    } catch (e) {
      debugPrint('AiSuiteProvider.fetchReallocation error: $e');
    }
  }

  Future<void> fetchAnomali() async {
    try {
      final res = await ApiService.get('/ai/anomali');
      if (res == null || res['status'] != 'success' || res['data'] == null) {
        return;
      }
      final list = res['data'] as List;
      _daftarAnomali
        ..clear()
        ..addAll(list.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return AnomaliModel(
            id: (map['id'] as num).toInt(),
            judul: map['judul'] as String? ?? 'Anomali',
            unitKasus: map['unit_kasus'] as String? ?? '-',
            unitPembanding: map['unit_pembanding'] as String? ?? '-',
            tingkatKeparahan: map['tingkat_keparahan'] as String? ?? 'SEDANG',
            deskripsi: map['deskripsi'] as String? ?? '',
            potensiKerugian: map['potensi_kerugian'] as String? ?? '-',
            waktuDeteksi:
                DateTime.tryParse(map['waktu_deteksi']?.toString() ?? '') ??
                    DateTime.now(),
          );
        }));
      notifyListeners();
    } catch (e) {
      debugPrint('AiSuiteProvider.fetchAnomali error: $e');
    }
  }

  void setHorizonHari(int hari) {
    if (_horizonHari == hari) return;
    _horizonHari = hari;
    notifyListeners();
    fetchPrediksi();
  }

  void setPersenAlokasi(double persen) {
    _persenAlokasiSurplus = persen;
    notifyListeners();
  }

  void setujuiRealokasiStok(int id) {
    final idx = _daftarRealokasi.indexWhere((r) => r.id == id);
    if (idx != -1) {
      _daftarRealokasi[idx].status = StatusRekomendasi.disetujui;
      notifyListeners();
    }
  }

  void tolakRealokasiStok(int id) {
    final idx = _daftarRealokasi.indexWhere((r) => r.id == id);
    if (idx != -1) {
      _daftarRealokasi[idx].status = StatusRekomendasi.ditolak;
      notifyListeners();
    }
  }

  void selesaikanAnomali(int id) {
    final idx = _daftarAnomali.indexWhere((a) => a.id == id);
    if (idx != -1) {
      _daftarAnomali[idx].isDiselesaikan = true;
      notifyListeners();
    }
  }

  String _periodeLabel(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '-';
    return DateFormat('dd/MM').format(parsed);
  }
}
