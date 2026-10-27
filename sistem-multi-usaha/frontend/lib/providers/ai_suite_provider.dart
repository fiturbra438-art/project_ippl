import 'package:flutter/material.dart';
import '../models/ai_models.dart';

class AiSuiteProvider extends ChangeNotifier {
  // 1. Prediksi Permintaan 7 & 30 Hari
  int _horizonHari = 7; // 7 atau 30
  int _selectedProdukId = 1;

  final List<PermintaanPrediksiModel> _prediksi7Hari = [];
  final List<PermintaanPrediksiModel> _prediksi30Hari = [];

  // 2. Realokasi Stok AI
  final List<RealokasiStokAiModel> _daftarRealokasi = [];

  // 3. Deteksi Anomali Antar Unit Sejenis
  final List<AnomaliModel> _daftarAnomali = [];

  // 4. Simulasi Alokasi Modal & Cash Flow Surplus
  int _unitSumberSurplus = 0;
  int _unitPenerimaModal = 0;
  double _persenAlokasiSurplus = 30.0;

  int get horizonHari => _horizonHari;
  int get selectedProdukId => _selectedProdukId;
  List<PermintaanPrediksiModel> get listPrediksi =>
      _horizonHari == 7 ? _prediksi7Hari : _prediksi30Hari;
  List<PermintaanPrediksiModel> get prediksiList => listPrediksi;
  List<RealokasiStokAiModel> get daftarRealokasi => _daftarRealokasi;
  List<AnomaliModel> get daftarAnomali => _daftarAnomali;

  int get unitSumberSurplus => _unitSumberSurplus;
  int get unitPenerimaModal => _unitPenerimaModal;
  double get persenAlokasiSurplus => _persenAlokasiSurplus;

  double get nominalSurplusKasLaundry => 0;
  double get modalDialokasikan => (nominalSurplusKasLaundry * _persenAlokasiSurplus) / 100;
  double get proyeksiKenaikanOmzetPenerima => modalDialokasikan * 1.85; // ROI 185%
  double get proyeksiPertumbuhanPersenPenerima => 4.5 + (_persenAlokasiSurplus * 0.45);

  void setHorizonHari(int hari) {
    _horizonHari = hari;
    notifyListeners();
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
}
