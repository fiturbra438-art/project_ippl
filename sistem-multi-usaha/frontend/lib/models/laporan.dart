class LaporanSummary {
  final double totalPemasukan;
  final double totalPengeluaran;
  final double labaOperasional;
  final double marginLabaPersen;
  final List<KategoriPengeluaran> rincianPengeluaran;
  final List<PerformaUnitLaporan> performaUnit;

  LaporanSummary({
    required this.totalPemasukan,
    required this.totalPengeluaran,
    required this.labaOperasional,
    required this.marginLabaPersen,
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
