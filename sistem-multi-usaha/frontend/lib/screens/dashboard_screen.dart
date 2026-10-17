import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/dashboard_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import '../models/usaha.dart';
import 'usaha_screen.dart';
import 'transaksi_screen.dart';
import 'portofolio_screen.dart';
import 'forecast_screen.dart';
import 'login_screen.dart';
import 'produk_screen.dart';
import 'laporan_screen.dart';
import 'chat_ai_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              backgroundColor: AppTheme.surfaceWhite,
              elevation: 0,
              centerTitle: false,
              title: const Text(
                'MultiUsaha',
                style: TextStyle(
                  color: AppTheme.primaryBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.textPrimary),
                  onPressed: () {},
                ),
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.lightBlueBg,
                  child: Text(
                    'AD',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            )
          : null,
      drawer: isMobile ? _buildNavigationDrawer(context) : null,
      body: Row(
        children: [
          // Desktop & Tablet Navigation Sidebar
          if (!isMobile) _buildDesktopSidebar(context),
          
          // Main Content View
          Expanded(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 32,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMobile) _buildDesktopHeader(context),
                    if (!isMobile) const SizedBox(height: 28),
                    _buildOverviewCards(context),
                    const SizedBox(height: 32),
                    _buildBusinessUnitsSection(context),
                    const SizedBox(height: 32),
                    _buildAllocationRecommendationCard(context),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMobile ? _buildMobileBottomBar(context) : null,
    );
  }

  // Header Desktop
  Widget _buildDesktopHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Ringkasan Portofolio Usaha',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Pantau performa finansial seluruh unit usaha Anda secara real-time.',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ],
        ),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Filter Periode'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.cardBorder),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Tambah Usaha'),
            ),
          ],
        ),
      ],
    );
  }

  // Kartu Ringkasan Finansial
  Widget _buildOverviewCards(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;
        final cardWidth = isNarrow ? constraints.maxWidth : (constraints.maxWidth - 32) / 3;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard(
              title: 'Total Pendapatan',
              value: currency.format(provider.totalPendapatan),
              badgeText: '+12.5% bln ini',
              isBadgePositive: true,
              icon: Icons.trending_up_rounded,
              iconColor: AppTheme.primaryBlue,
              iconBg: AppTheme.lightBlueBg,
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Total Pengeluaran',
              value: currency.format(provider.totalPengeluaran),
              badgeText: 'Terkendali',
              isBadgePositive: true,
              icon: Icons.account_balance_wallet_outlined,
              iconColor: AppTheme.textSecondary,
              iconBg: const Color(0xFFF1F5F9),
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Total Laba Bersih',
              value: currency.format(provider.totalLabaBersih),
              badgeText: '+18.2% margin',
              isBadgePositive: true,
              icon: Icons.monetization_on_outlined,
              iconColor: AppTheme.accentGreen,
              iconBg: AppTheme.lightGreenBg,
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String badgeText,
    required bool isBadgePositive,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isBadgePositive ? AppTheme.lightGreenBg : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: isBadgePositive ? AppTheme.accentGreen : const Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // Daftar Unit Usaha
  Widget _buildBusinessUnitsSection(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Unit Usaha Aktif',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () {},
              child: const Text('Lihat Semua', style: TextStyle(color: AppTheme.primaryBlue)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: provider.daftarUsaha.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final usaha = provider.daftarUsaha[index];
            return _buildBusinessUnitCard(usaha, currency);
          },
        ),
      ],
    );
  }

  Widget _buildBusinessUnitCard(UsahaModel usaha, NumberFormat currency) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppTheme.lightBlueBg,
            child: const Icon(Icons.storefront_rounded, color: AppTheme.primaryBlue, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      usaha.nama,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildTag(usaha.kategoriPortofolio),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${usaha.jenisUsaha} • ${usaha.lokasi}',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currency.format(usaha.pendapatanBulanIni),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '+${usaha.pertumbuhanPersen}%',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String kategori) {
    Color bg = AppTheme.lightBlueBg;
    Color text = AppTheme.primaryBlue;

    if (kategori == 'Star') {
      bg = const Color(0xFFFEF3C7);
      text = const Color(0xFFD97706);
    } else if (kategori == 'Cash Cow') {
      bg = AppTheme.lightGreenBg;
      text = AppTheme.accentGreen;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        kategori,
        style: TextStyle(color: text, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  // Rekomendasi Alokasi Modal (Insight BCG & AI)
  Widget _buildAllocationRecommendationCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E40AF), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(38),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Rekomendasi Alokasi Modal Portofolio',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Surplus kas dari "Laundry Bersih Kilat" (Cash Cow) disarankan dialokasikan 20% ke "Kedai Kopi Bahagia" (Star) untuk ekspansi inventaris.',
                  style: TextStyle(color: Color(0xFFDBEAFE), fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text('Detail Analisis'),
          ),
        ],
      ),
    );
  }

  // Sidebar Desktop
  Widget _buildDesktopSidebar(BuildContext context) {
    final provider = context.watch<DashboardProvider>();

    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceWhite,
        border: Border(right: BorderSide(color: AppTheme.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: const [
                Icon(Icons.hub_rounded, color: AppTheme.primaryBlue, size: 28),
                SizedBox(width: 12),
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
          const SizedBox(height: 36),
          _buildSidebarItem(context, 0, Icons.dashboard_rounded, 'Dashboard', () {}),
          _buildSidebarItem(context, 1, Icons.storefront_rounded, 'Unit Usaha', () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UsahaScreen()));
          }),
          _buildSidebarItem(context, 2, Icons.inventory_2_rounded, 'Inventaris & Produk', () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProdukScreen()));
          }),
          _buildSidebarItem(context, 3, Icons.receipt_long_rounded, 'Transaksi', () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TransaksiScreen()));
          }),
          _buildSidebarItem(context, 4, Icons.assessment_rounded, 'Laporan Keuangan', () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LaporanScreen()));
          }),
          _buildSidebarItem(context, 5, Icons.pie_chart_rounded, 'Portofolio BCG', () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PortofolioScreen()));
          }),
          _buildSidebarItem(context, 6, Icons.trending_up_rounded, 'Forecasting', () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ForecastScreen()));
          }),
          _buildSidebarItem(context, 7, Icons.smart_toy_rounded, 'Asisten AI', () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ChatAiScreen()));
          }),
          const Spacer(),
          const Divider(color: AppTheme.cardBorder),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppTheme.lightBlueBg,
              child: Text('AD', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
            ),
            title: const Text('Admin Owner', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const Text('admin@usaha.com', style: TextStyle(fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.logout_rounded, size: 20, color: AppTheme.textSecondary),
              onPressed: () {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(BuildContext context, int index, IconData icon, String label, VoidCallback onTap) {
    final provider = context.watch<DashboardProvider>();
    final isSelected = provider.selectedNavIndex == index;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.lightBlueBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary,
          size: 22,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        onTap: () {
          provider.setNavIndex(index);
          onTap();
        },
      ),
    );
  }

  // Drawer Mobile
  Widget _buildNavigationDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: AppTheme.primaryBlue),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('MultiUsaha', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Sistem Manajemen Portofolio', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_rounded, color: AppTheme.primaryBlue),
            title: const Text('Dashboard'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.storefront_rounded),
            title: const Text('Unit Usaha'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UsahaScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_rounded),
            title: const Text('Transaksi'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TransaksiScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.assessment_rounded),
            title: const Text('Laporan Keuangan'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LaporanScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.pie_chart_rounded),
            title: const Text('Portofolio BCG'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PortofolioScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.trending_up_rounded),
            title: const Text('Forecasting'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ForecastScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_rounded),
            title: const Text('Asisten AI'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ChatAiScreen()));
            },
          ),
        ],
      ),
    );
  }

  // Bottom Navigation Bar Mobile
  Widget _buildMobileBottomBar(BuildContext context) {
    final provider = context.watch<DashboardProvider>();

    return BottomNavigationBar(
      currentIndex: provider.selectedNavIndex,
      onTap: (index) {
        provider.setNavIndex(index);
        if (index == 1) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UsahaScreen()));
        } else if (index == 2) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TransaksiScreen()));
        } else if (index == 3) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PortofolioScreen()));
        }
      },
      selectedItemColor: AppTheme.primaryBlue,
      unselectedItemColor: AppTheme.textSecondary,
      type: BottomNavigationBarType.fixed,
      backgroundColor: AppTheme.surfaceWhite,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
        BottomNavigationBarItem(icon: Icon(Icons.storefront_rounded), label: 'Usaha'),
        BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'Transaksi'),
        BottomNavigationBarItem(icon: Icon(Icons.pie_chart_rounded), label: 'Portofolio'),
      ],
    );
  }
}
