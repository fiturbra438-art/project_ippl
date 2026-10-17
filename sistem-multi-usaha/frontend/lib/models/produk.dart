class ProdukModel {
  final int id;
  final int unitId;
  final String nama;
  final String sku;
  final double hargaBeli;
  final double hargaJual;
  final int stok;
  final int minStok;

  ProdukModel({
    required this.id,
    required this.unitId,
    required this.nama,
    required this.sku,
    required this.hargaBeli,
    required this.hargaJual,
    required this.stok,
    this.minStok = 5,
  });

  double get marginKeuntungan => hargaJual - hargaBeli;
  bool get isStokKritis => stok <= minStok;
}
