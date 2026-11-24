import 'package:flutter/material.dart';
import '../models/notifikasi_model.dart';

class NotifikasiProvider extends ChangeNotifier {
  final List<NotifikasiItem> _daftarNotifikasi = [];

  List<NotifikasiItem> get daftarNotifikasi => _daftarNotifikasi;
  int get unreadCount => _daftarNotifikasi.where((n) => !n.isDibaca).length;

}
