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
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/produk_screen.dart';
import 'screens/laporan_screen.dart';
import 'screens/chat_ai_screen.dart';
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
      title: 'MultiUsaha - Sistem Manajemen Portofolio Bisnis',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const DashboardScreen(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/produk': (_) => const ProdukScreen(),
        '/laporan': (_) => const LaporanScreen(),
        '/chat': (_) => const ChatAiScreen(),
      },
    );
  }
}
