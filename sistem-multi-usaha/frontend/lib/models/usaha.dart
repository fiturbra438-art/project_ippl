class UsahaModel {
  final int id;
  final String nama;
  final String jenisUsaha;
  final String lokasi;
  final String kategoriPortofolio; // 'Star', 'Cash Cow', 'Question Mark', 'Dog'
  final double pendapatanBulanIni;
  final double pengeluaranBulanIni;
  final double pertumbuhanPersen;
  final bool status;
  final bool hasPos; // true = pakai kasir POS (kafe, toko retail), false = tidak pakai POS (gudang pusat, distribusi grosir, kantor)

  UsahaModel({
    required this.id,
    required this.nama,
    required this.jenisUsaha,
    required this.lokasi,
    required this.kategoriPortofolio,
    required this.pendapatanBulanIni,
    required this.pengeluaranBulanIni,
    required this.pertumbuhanPersen,
    this.status = true,
    this.hasPos = true,
  });

  double get labaBersih => pendapatanBulanIni - pengeluaranBulanIni;
}
