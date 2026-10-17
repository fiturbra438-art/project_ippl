enum StatusTransfer { pending, diterima, ditolak }

class TransferStokModel {
  final int id;
  final int unitAsalId;
  final String namaUnitAsal;
  final int unitTujuanId;
  final String namaUnitTujuan;
  final int produkId;
  final String namaProduk;
  final int jumlah;
  final DateTime waktuKirim;
  DateTime? waktuTerima;
  StatusTransfer status;

  TransferStokModel({
    required this.id,
    required this.unitAsalId,
    required this.namaUnitAsal,
    required this.unitTujuanId,
    required this.namaUnitTujuan,
    required this.produkId,
    required this.namaProduk,
    required this.jumlah,
    required this.waktuKirim,
    this.waktuTerima,
    this.status = StatusTransfer.pending,
  });
}

class StokOpnameModel {
  final int id;
  final int unitId;
  final String namaUnit;
  final String namaProduk;
  final int stokSistem;
  final int stokFisik;
  final String alasan;
  final DateTime tanggal;

  StokOpnameModel({
    required this.id,
    required this.unitId,
    required this.namaUnit,
    required this.namaProduk,
    required this.stokSistem,
    required this.stokFisik,
    required this.alasan,
    required this.tanggal,
  });

  int get selisih => stokFisik - stokSistem;
}

class MutasiStokModel {
  final int id;
  final String jenis; // 'MASUK', 'KELUAR'
  final String namaProduk;
  final int jumlah;
  final String sumberTujuan; // misal: Pemasok A, Konsumsi Kafe
  final DateTime tanggal;

  MutasiStokModel({
    required this.id,
    required this.jenis,
    required this.namaProduk,
    required this.jumlah,
    required this.sumberTujuan,
    required this.tanggal,
  });
}
