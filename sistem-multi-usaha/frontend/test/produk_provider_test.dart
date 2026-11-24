import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_multi_usaha/models/produk.dart';
import 'package:frontend_multi_usaha/providers/produk_provider.dart';

ProdukModel _product() => ProdukModel(
      id: 8,
      unitId: 3,
      nama: 'Produk Uji',
      sku: 'TEST-8',
      hargaBeli: 10,
      hargaJual: 20,
      stok: 5,
    );

void main() {
  test('stock adjustment commits local value after API success', () async {
    final response = Completer<Map<String, dynamic>?>();
    final provider = ProdukProvider(patch: (_, __) => response.future);
    provider.tambahProduk(_product());

    final update = provider.updateStok(8, 1);
    expect(provider.daftarProduk.single.stok, 5);
    response.complete({'status': 'success'});

    expect(await update, isTrue);
    expect(provider.daftarProduk.single.stok, 6);
  });

  test('stock adjustment failure preserves server-backed value', () async {
    final provider = ProdukProvider(
      patch: (_, __) async => {
        'status': 'error',
        'message': 'Stok ditolak server',
      },
    );
    provider.tambahProduk(_product());

    expect(await provider.updateStok(8, -1), isFalse);
    expect(provider.daftarProduk.single.stok, 5);
    expect(provider.lastError, 'Stok ditolak server');
  });
}
