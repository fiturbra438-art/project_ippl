import 'package:flutter/material.dart';
import '../models/portofolio.dart';

class PortofolioProvider extends ChangeNotifier {
  final List<BCGItem> _items = [
    BCGItem(
      id: 1,
      namaUsaha: 'Kedai Kopi Bahagia',
      kategori: 'Star',
      growthRate: 18.5,
      marketShare: 1.6,
      arusKas: 17300000,
      rekomendasi: 'Pertahankan investasi ekspansi cabang dan automasi mesin.',
    ),
    BCGItem(
      id: 2,
      namaUsaha: 'Laundry Bersih Kilat',
      kategori: 'Cash Cow',
      growthRate: 4.8,
      marketShare: 1.8,
      arusKas: 16600000,
      rekomendasi: 'Maksimalkan profit stabil, alokasikan kas surplus untuk unit berkembang.',
    ),
    BCGItem(
      id: 3,
      namaUsaha: 'Toko Elektronik Digital',
      kategori: 'Question Mark',
      growthRate: 24.0,
      marketShare: 0.6,
      arusKas: 7900000,
      rekomendasi: 'Tingkatkan promosi online atau pertimbangkan pivot produk spesifik.',
    ),
    BCGItem(
      id: 4,
      namaUsaha: 'Depot Air Minum Mitra',
      kategori: 'Dog',
      growthRate: 1.2,
      marketShare: 0.4,
      arusKas: 1200000,
      rekomendasi: 'Evaluasi operasional atau pertimbangkan efisiensi biaya ketat / divestasi.',
    ),
  ];

  List<BCGItem> get items => _items;

  List<BCGItem> getByKategori(String kategori) =>
      _items.where((i) => i.kategori == kategori).toList();
}
