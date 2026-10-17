enum JenisTransaksi { pemasukan, pengeluaran }

class TransaksiModel {
  final int id;
  final int unitId;
  final String namaUnit;
  final DateTime tanggal;
  final JenisTransaksi jenis;
  final String kategori;
  final double jumlah;
  final String keterangan;

  TransaksiModel({
    required this.id,
    required this.unitId,
    required this.namaUnit,
    required this.tanggal,
    required this.jenis,
    required this.kategori,
    required this.jumlah,
    required this.keterangan,
  });
}
