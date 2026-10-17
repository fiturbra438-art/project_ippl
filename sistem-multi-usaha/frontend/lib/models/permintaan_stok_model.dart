enum StatusPermintaanStok { pending, disetujui, ditolak, selesai }

class PermintaanStokModel {
  final int id;
  final int unitId;
  final String namaUnit;
  final String pemohon;
  final String namaProduk;
  final int jumlahDiminta;
  final String alasan;
  final DateTime waktuPengajuan;
  StatusPermintaanStok status;

  PermintaanStokModel({
    required this.id,
    required this.unitId,
    required this.namaUnit,
    required this.pemohon,
    required this.namaProduk,
    required this.jumlahDiminta,
    required this.alasan,
    required this.waktuPengajuan,
    this.status = StatusPermintaanStok.pending,
  });
}
