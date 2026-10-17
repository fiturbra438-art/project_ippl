class BCGItem {
  final int id;
  final String namaUsaha;
  final String kategori; // 'Star', 'Cash Cow', 'Question Mark', 'Dog'
  final double growthRate; // misal: 18.5%
  final double marketShare; // misal: 1.4x relatif
  final double arusKas; // surplus/defisit
  final String rekomendasi;

  BCGItem({
    required this.id,
    required this.namaUsaha,
    required this.kategori,
    required this.growthRate,
    required this.marketShare,
    required this.arusKas,
    required this.rekomendasi,
  });
}
