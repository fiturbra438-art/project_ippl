import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/usaha_provider.dart';
import 'providers/transaksi_provider.dart';
import 'providers/portofolio_provider.dart';
import 'providers/forecast_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/produk_provider.dart';
import 'providers/laporan_provider.dart';
import 'providers/chat_ai_provider.dart';
import 'providers/pos_provider.dart';
import 'providers/gudang_provider.dart';
import 'providers/permintaan_stok_provider.dart';
import 'providers/ai_suite_provider.dart';
import 'providers/notifikasi_provider.dart';

import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/produk_screen.dart';
import 'screens/laporan_screen.dart';
import 'screens/chat_ai_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/gudang_screen.dart';
import 'screens/permintaan_stok_screen.dart';
import 'screens/ai_hub_screen.dart';
import 'screens/user_management_screen.dart';
import 'screens/notifikasi_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => UsahaProvider()),
        ChangeNotifierProvider(create: (_) => TransaksiProvider()),
        ChangeNotifierProvider(create: (_) => PortofolioProvider()),
        ChangeNotifierProvider(create: (_) => ForecastProvider()),
        ChangeNotifierProvider(create: (_) => ProdukProvider()),
        ChangeNotifierProvider(create: (_) => LaporanProvider()),
        ChangeNotifierProvider(create: (_) => ChatAiProvider()),
        ChangeNotifierProvider(create: (_) => PosProvider()),
        ChangeNotifierProvider(create: (_) => GudangProvider()),
        ChangeNotifierProvider(create: (_) => PermintaanStokProvider()),
        ChangeNotifierProvider(create: (_) => AiSuiteProvider()),
        ChangeNotifierProvider(create: (_) => NotifikasiProvider()),
      ],
      child: const MultiUsahaApp(),
    ),
  );
}

class MultiUsahaApp extends StatelessWidget {
  const MultiUsahaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MultiUsaha - Sistem Manajemen Portofolio Bisnis Terintegrasi AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const DashboardScreen(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/pos': (_) => const PosScreen(),
        '/gudang': (_) => const GudangScreen(),
        '/produk': (_) => const ProdukScreen(),
        '/laporan': (_) => const LaporanScreen(),
        '/permintaan-stok': (_) => const PermintaanStokScreen(),
        '/ai-hub': (_) => const AiHubScreen(),
        '/chat': (_) => const ChatAiScreen(),
        '/users': (_) => const UserManagementScreen(),
        '/notifikasi': (_) => const NotifikasiScreen(),
      },
    );
  }
}
