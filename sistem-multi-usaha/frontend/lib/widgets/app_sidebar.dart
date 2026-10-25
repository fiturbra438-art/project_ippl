import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../screens/dashboard_screen.dart';
import '../screens/manager_dashboard_screen.dart';
import '../screens/usaha_screen.dart';
import '../screens/pos_screen.dart';
import '../screens/gudang_screen.dart';
import '../screens/produk_screen.dart';
import '../screens/permintaan_stok_screen.dart';
import '../screens/transaksi_screen.dart';
import '../screens/laporan_screen.dart';
import '../screens/portofolio_screen.dart';
import '../screens/forecast_screen.dart';
import '../screens/ai_hub_screen.dart';
import '../screens/chat_ai_screen.dart';
import '../screens/user_management_screen.dart';
import '../screens/login_screen.dart';

class AppSidebar extends StatelessWidget {
  final String activeRoute;

  const AppSidebar({super.key, required this.activeRoute});

  void _navigateWithoutAnimation(BuildContext context, Widget targetScreen) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, _, __) => targetScreen,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = auth.currentUser?.role ?? UserRole.owner;

    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceWhite,
        border: Border(right: BorderSide(color: AppTheme.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: const [
                Icon(Icons.hub_rounded, color: AppTheme.primaryBlue, size: 28),
                SizedBox(width: 10),
                Text(
                  'MultiUsaha',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildItem(context, 'Dashboard', Icons.dashboard_rounded, activeRoute == 'dashboard', () {
                  if (activeRoute != 'dashboard') {
                    if (role == UserRole.manager) {
                      _navigateWithoutAnimation(context, const ManagerDashboardScreen());
                    } else {
                      _navigateWithoutAnimation(context, const DashboardScreen());
                    }
                  }
                }),
                if (role == UserRole.owner || role == UserRole.manager)
                  _buildItem(context, 'Kelola Unit Usaha', Icons.storefront_rounded, activeRoute == 'usaha', () {
                    if (activeRoute != 'usaha') {
                      _navigateWithoutAnimation(context, const UsahaScreen());
                    }
                  }),
                // Kasir (POS) diutamakan di aplikasi native desktop/mobile, pada web hanya ditampilkan jika owner
                if (!kIsWeb && (role == UserRole.owner || role == UserRole.kasir))
                  _buildItem(context, 'Kasir (POS)', Icons.point_of_sale_rounded, activeRoute == 'pos', () {
                    if (activeRoute != 'pos') {
                      _navigateWithoutAnimation(context, const PosScreen());
                    }
                  })
                else if (kIsWeb && role == UserRole.owner)
                  _buildItem(context, 'Monitor POS', Icons.point_of_sale_rounded, activeRoute == 'pos', () {
                    if (activeRoute != 'pos') {
                      _navigateWithoutAnimation(context, const PosScreen());
                    }
                  }),
                if (role == UserRole.owner || role == UserRole.adminGudang || role == UserRole.manager)
                  _buildItem(context, 'Gudang & Transfer', Icons.warehouse_rounded, activeRoute == 'gudang', () {
                    if (activeRoute != 'gudang') {
                      _navigateWithoutAnimation(context, const GudangScreen());
                    }
                  }),
                if (role == UserRole.owner || role == UserRole.adminGudang || role == UserRole.manager)
                  _buildItem(context, 'Katalog Produk', Icons.inventory_2_rounded, activeRoute == 'produk', () {
                    if (activeRoute != 'produk') {
                      _navigateWithoutAnimation(context, const ProdukScreen());
                    }
                  }),
                if (role == UserRole.owner || role == UserRole.manager)
                  _buildItem(context, 'Permintaan Stok', Icons.add_shopping_cart_rounded, activeRoute == 'permintaan_stok', () {
                    if (activeRoute != 'permintaan_stok') {
                      _navigateWithoutAnimation(context, const PermintaanStokScreen());
                    }
                  }),
                if (role == UserRole.owner || role == UserRole.kasir || role == UserRole.manager)
                  _buildItem(context, 'Transaksi Kas', Icons.receipt_long_rounded, activeRoute == 'transaksi', () {
                    if (activeRoute != 'transaksi') {
                      _navigateWithoutAnimation(context, const TransaksiScreen());
                    }
                  }),
                if (role == UserRole.owner || role == UserRole.manager || role == UserRole.auditor)
                  _buildItem(context, 'Laporan Keuangan', Icons.assessment_rounded, activeRoute == 'laporan', () {
                    if (activeRoute != 'laporan') {
                      _navigateWithoutAnimation(context, const LaporanScreen());
                    }
                  }),
                if (role == UserRole.owner) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Divider(color: AppTheme.cardBorder),
                  ),
                  _buildItem(context, 'AI Suite (Owner)', Icons.auto_awesome_rounded, activeRoute == 'ai_hub', () {
                    if (activeRoute != 'ai_hub') {
                      _navigateWithoutAnimation(context, const AiHubScreen());
                    }
                  }),
                  _buildItem(context, 'Portofolio BCG', Icons.pie_chart_rounded, activeRoute == 'portofolio', () {
                    if (activeRoute != 'portofolio') {
                      _navigateWithoutAnimation(context, const PortofolioScreen());
                    }
                  }),
                  _buildItem(context, 'Forecasting AI', Icons.trending_up_rounded, activeRoute == 'forecast', () {
                    if (activeRoute != 'forecast') {
                      _navigateWithoutAnimation(context, const ForecastScreen());
                    }
                  }),
                  _buildItem(context, 'Chatbot BI AI', Icons.smart_toy_rounded, activeRoute == 'chat_ai', () {
                    if (activeRoute != 'chat_ai') {
                      _navigateWithoutAnimation(context, const ChatAiScreen());
                    }
                  }),
                  _buildItem(context, 'Kelola Pengguna', Icons.manage_accounts_rounded, activeRoute == 'users', () {
                    if (activeRoute != 'users') {
                      _navigateWithoutAnimation(context, const UserManagementScreen());
                    }
                  }),
                ],
              ],
            ),
          ),
          const Divider(color: AppTheme.cardBorder),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.lightBlueBg,
              child: Text(
                auth.currentUser?.nama.isNotEmpty == true ? auth.currentUser!.nama[0] : 'U',
                style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(auth.currentUser?.nama ?? 'User', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(auth.currentUser?.role.label ?? 'Owner', style: const TextStyle(fontSize: 11)),
            trailing: IconButton(
              icon: const Icon(Icons.logout_rounded, size: 18, color: AppTheme.textSecondary),
              onPressed: () {
                auth.logout();
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.lightBlueBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        visualDensity: const VisualDensity(vertical: -3),
        leading: Icon(
          icon,
          color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary,
          size: 20,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
