enum StatusRekomendasi { pending, disetujui, ditolak }

class RealokasiStokAiModel {
  final int id;
  final String namaProduk;
  final String unitSumber;
  final String unitTujuan;
  final int jumlahPindah;
  final String alasanAi;
  final double estimasiHematBiaya;
  StatusRekomendasi status;

  RealokasiStokAiModel({
    required this.id,
    required this.namaProduk,
    required this.unitSumber,
    required this.unitTujuan,
    required this.jumlahPindah,
    required this.alasanAi,
    required this.estimasiHematBiaya,
    this.status = StatusRekomendasi.pending,
  });
}

class AnomaliModel {
  final int id;
  final String judul;
  final String unitKasus;
  final String unitPembanding;
  final String tingkatKeparahan; // 'TINGGI', 'SEDANG'
  final String deskripsi;
  final String potensiKerugian;
  final DateTime waktuDeteksi;
  bool isDiselesaikan;

  AnomaliModel({
    required this.id,
    required this.judul,
    required this.unitKasus,
    required this.unitPembanding,
    required this.tingkatKeparahan,
    required this.deskripsi,
    required this.potensiKerugian,
    required this.waktuDeteksi,
    this.isDiselesaikan = false,
  });
}

class PermintaanPrediksiModel {
  final String periode; // Hari ke-1 s/d Hari ke-30
  final double aktual;
  final double prediksi;
  final String statusRisiko; // 'NORMAL', 'RISIKO_KEHABISAN', 'RISIKO_KELEBIHAN'

  PermintaanPrediksiModel({
    required this.periode,
    this.aktual = 0,
    required this.prediksi,
    required this.statusRisiko,
  });
}
