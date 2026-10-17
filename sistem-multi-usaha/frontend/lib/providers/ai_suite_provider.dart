import 'package:flutter/material.dart';
import '../models/ai_models.dart';

class AiSuiteProvider extends ChangeNotifier {
  // 1. Prediksi Permintaan 7 & 30 Hari
  int _horizonHari = 7; // 7 atau 30
  int _selectedProdukId = 1;

  final List<PermintaanPrediksiModel> _prediksi7Hari = [
    PermintaanPrediksiModel(periode: 'Hari 1', aktual: 42, prediksi: 40, statusRisiko: 'NORMAL'),
    PermintaanPrediksiModel(periode: 'Hari 2', aktual: 38, prediksi: 44, statusRisiko: 'NORMAL'),
    PermintaanPrediksiModel(periode: 'Hari 3', aktual: 0, prediksi: 58, statusRisiko: 'RISIKO_KEHABISAN'),
    PermintaanPrediksiModel(periode: 'Hari 4', aktual: 0, prediksi: 65, statusRisiko: 'RISIKO_KEHABISAN'),
    PermintaanPrediksiModel(periode: 'Hari 5', aktual: 0, prediksi: 35, statusRisiko: 'NORMAL'),
    PermintaanPrediksiModel(periode: 'Hari 6', aktual: 0, prediksi: 28, statusRisiko: 'RISIKO_KELEBIHAN'),
    PermintaanPrediksiModel(periode: 'Hari 7', aktual: 0, prediksi: 48, statusRisiko: 'NORMAL'),
  ];

  final List<PermintaanPrediksiModel> _prediksi30Hari = List.generate(
    30,
    (index) => PermintaanPrediksiModel(
      periode: 'Hari ${index + 1}',
      prediksi: 35.0 + (index % 5) * 8.0,
      statusRisiko: (index == 12 || index == 18)
          ? 'RISIKO_KEHABISAN'
          : (index == 24 ? 'RISIKO_KELEBIHAN' : 'NORMAL'),
    ),
  );

  // 2. Realokasi Stok AI
  final List<RealokasiStokAiModel> _daftarRealokasi = [
    RealokasiStokAiModel(
      id: 1,
      namaProduk: 'Fast Charger Type-C 30W',
      unitSumber: 'Toko Elektronik Digital (Stok: 35, Penjualan Lambat)',
      unitTujuan: 'Kedai Kopi Bahagia (Stok: 0, Permintaan Pelanggan Tinggi)',
      jumlahPindah: 15,
      alasanAi: 'Cabang Toko Elektronik kelebihan stok 30 hari, sedangkan kafe memiliki lonjakan pengunjung mencari charger.',
      estimasiHematBiaya: 450000,
      status: StatusRekomendasi.pending,
    ),
    RealokasiStokAiModel(
      id: 2,
      namaProduk: 'Deterjen Konsentrat 5L',
      unitSumber: 'Gudang Pusat Cikarang (Surplus 80 unit)',
      unitTujuan: 'Laundry Bersih Kilat (Sisa 4 unit)',
      jumlahPindah: 20,
      alasanAi: 'Mencegah stockout operasional cuci dalam 48 jam ke depan tanpa perlu order beli baru.',
      estimasiHematBiaya: 850000,
      status: StatusRekomendasi.pending,
    ),
  ];

  // 3. Deteksi Anomali Antar Unit Sejenis
  final List<AnomaliModel> _daftarAnomali = [
    AnomaliModel(
      id: 1,
      judul: 'Konsumsi Bahan Baku Biji Kopi Anomali (+42%)',
      unitKasus: 'Kedai Kopi Cabang 1 (Jl. Merdeka)',
      unitPembanding: 'Kedai Kopi Cabang 2 (Mall Sentral)',
      tingkatKeparahan: 'TINGGI',
      deskripsi: 'Cabang 1 mencatatkan volume pemakaian biji kopi 42% lebih tinggi per cup minuman dibandingkan Cabang 2 untuk resep yang sama. Terindikasi kebocoran bahan atau spillage berlebih.',
      potensiKerugian: 'Rp 4.200.000 / bln',
      waktuDeteksi: DateTime.now().subtract(const Duration(hours: 5)),
      isDiselesaikan: false,
    ),
    AnomaliModel(
      id: 2,
      judul: 'Rasio Void & Diskon Kasir di Luar Batas Standar',
      unitKasus: 'Kasir Shift Sore (Kedai Kopi)',
      unitPembanding: 'Rata-rata Historis Seluruh Kasir',
      tingkatKeparahan: 'SEDANG',
      deskripsi: 'Frekuensi pembatalan transaksi (void) mencapai 18% dari total bill, 3x lebih tinggi dari standar audit (5%).',
      potensiKerugian: 'Rp 1.850.000 / bln',
      waktuDeteksi: DateTime.now().subtract(const Duration(days: 1)),
      isDiselesaikan: false,
    ),
  ];

  // 4. Simulasi What-If Alokasi Modal
  double _persenAlokasiSurplus = 20.0;
  int _unitSumberSurplus = 2; // Laundry (Cash Cow)
  int _unitPenerimaModal = 3; // Toko Elektronik (Question Mark)

  int get horizonHari => _horizonHari;
  int get selectedProdukId => _selectedProdukId;
  List<PermintaanPrediksiModel> get listPrediksi => _horizonHari == 7 ? _prediksi7Hari : _prediksi30Hari;
  List<RealokasiStokAiModel> get daftarRealokasi => _daftarRealokasi;
  List<AnomaliModel> get daftarAnomali => _daftarAnomali;

  double get persenAlokasiSurplus => _persenAlokasiSurplus;
  int get unitSumberSurplus => _unitSumberSurplus;
  int get unitPenerimaModal => _unitPenerimaModal;

  // Nilai simulasi What-If dinamis
  double get nominalSurplusKasLaundry => 16600000; // Rp 16.6 jt
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
