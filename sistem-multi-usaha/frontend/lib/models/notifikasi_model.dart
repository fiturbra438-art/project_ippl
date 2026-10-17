enum JenisNotifikasi { stokMenipis, anomali, rekomendasiAi, transferStok }

class NotifikasiItem {
  final int id;
  final String judul;
  final String pesan;
  final JenisNotifikasi jenis;
  final DateTime waktu;
  bool isDibaca;

  NotifikasiItem({
    required this.id,
    required this.judul,
    required this.pesan,
    required this.jenis,
    required this.waktu,
    this.isDibaca = false,
  });
}
