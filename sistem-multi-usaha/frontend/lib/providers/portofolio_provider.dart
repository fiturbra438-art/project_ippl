import 'package:flutter/material.dart';
import '../models/portofolio.dart';

class PortofolioProvider extends ChangeNotifier {
  final List<BCGItem> _items = [];

  List<BCGItem> get items => _items;

  void setItems(List<BCGItem> items) {
    _items.clear();
    _items.addAll(items);
    notifyListeners();
  }

  List<BCGItem> getByKategori(String kategori) =>
      _items.where((i) => i.kategori == kategori).toList();
}
