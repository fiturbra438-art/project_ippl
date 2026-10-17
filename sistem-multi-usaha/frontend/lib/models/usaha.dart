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
  });

  double get labaBersih => pendapatanBulanIni - pengeluaranBulanIni;
}
