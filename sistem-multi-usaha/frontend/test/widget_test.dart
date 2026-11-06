import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend_multi_usaha/main.dart';
import 'package:frontend_multi_usaha/providers/auth_provider.dart';
import 'package:frontend_multi_usaha/providers/pos_provider.dart';
import 'package:frontend_multi_usaha/providers/produk_provider.dart';
import 'package:frontend_multi_usaha/providers/gudang_provider.dart';
import 'package:frontend_multi_usaha/providers/transaksi_provider.dart';
import 'package:frontend_multi_usaha/providers/laporan_provider.dart';
import 'package:frontend_multi_usaha/providers/permintaan_stok_provider.dart';
import 'package:frontend_multi_usaha/providers/notifikasi_provider.dart';

void main() {
  testWidgets('App smoke test renders login screen with MultiProvider',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PosProvider()),
          ChangeNotifierProvider(create: (_) => ProdukProvider()),
          ChangeNotifierProvider(create: (_) => GudangProvider()),
          ChangeNotifierProvider(create: (_) => TransaksiProvider()),
          ChangeNotifierProvider(create: (_) => LaporanProvider()),
          ChangeNotifierProvider(create: (_) => PermintaanStokProvider()),
          ChangeNotifierProvider(create: (_) => NotifikasiProvider()),
        ],
        child: const MultiUsahaApp(),
      ),
    );

    expect(find.textContaining('MultiUsaha'), findsWidgets);
  });
}
