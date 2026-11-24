class LaporanSummary {
  final double totalPemasukan;
  final double totalPengeluaran;
  final double labaOperasional;
  final double marginLabaPersen;
  final double omzetKotor;
  final double diskon;
  final double refund;
  final double omzetBersih;
  final double hpp;
  final List<KategoriPengeluaran> rincianPengeluaran;
  final List<PerformaUnitLaporan> performaUnit;

  LaporanSummary({
    required this.totalPemasukan,
    required this.totalPengeluaran,
    required this.labaOperasional,
    required this.marginLabaPersen,
    required this.omzetKotor,
    required this.diskon,
    required this.refund,
    required this.omzetBersih,
    required this.hpp,
    required this.rincianPengeluaran,
    required this.performaUnit,
  });
}

class KategoriPengeluaran {
  final String nama;
  final double nominal;
  final double persen;

  KategoriPengeluaran({
    required this.nama,
    required this.nominal,
    required this.persen,
  });
}

class PerformaUnitLaporan {
  final String namaUnit;
  final double pendapatan;
  final double pengeluaran;
  final double labaBersih;
  final double kontribusiPersen;

  PerformaUnitLaporan({
    required this.namaUnit,
    required this.pendapatan,
    required this.pengeluaran,
    required this.labaBersih,
    required this.kontribusiPersen,
  });
}
