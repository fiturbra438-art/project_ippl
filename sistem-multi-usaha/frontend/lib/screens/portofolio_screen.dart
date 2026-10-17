import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/portofolio.dart';
import '../providers/portofolio_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_sidebar.dart';
import 'dashboard_screen.dart';
import 'usaha_screen.dart';
import 'transaksi_screen.dart';

class PortofolioScreen extends StatelessWidget {
  const PortofolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              backgroundColor: AppTheme.surfaceWhite,
              elevation: 0,
              title: const Text(
                'Matriks Portofolio BCG',
                style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      drawer: isMobile ? _buildNavigationDrawer(context) : null,
      body: Row(
        children: [
          if (!isMobile) const AppSidebar(activeRoute: 'portofolio'),
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
                    if (!isMobile) _buildDesktopHeader(),
                    const SizedBox(height: 24),
                    _buildMatrixGrid(context, isMobile),
                    const SizedBox(height: 32),
                    _buildAdviceSummaryCard(),
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

  Widget _buildDesktopHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'Analisis Portofolio & Alokasi Modal (BCG Matrix)',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
        ),
        SizedBox(height: 4),
        Text(
          'Evaluasi posisi pertumbuhan pasar vs pangsa pasar relatif untuk strategi alokasi kas optimal.',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildMatrixGrid(BuildContext context, bool isMobile) {
    final provider = context.watch<PortofolioProvider>();

    final quadrants = [
      {
        'title': '⭐ STARS (Bintang)',
        'subtitle': 'Pertumbuhan Tinggi, Pangsa Pasar Tinggi',
        'color': const Color(0xFFD97706),
        'bg': const Color(0xFFFEF3C7),
        'borderColor': const Color(0xFFFDE68A),
        'items': provider.getByKategori('Star'),
      },
      {
        'title': '❓ QUESTION MARKS (Tanda Tanya)',
        'subtitle': 'Pertumbuhan Tinggi, Pangsa Pasar Rendah',
        'color': const Color(0xFF7E22CE),
        'bg': const Color(0xFFF3E8FF),
        'borderColor': const Color(0xFFE9D5FF),
        'items': provider.getByKategori('Question Mark'),
      },
      {
        'title': '🐄 CASH COWS (Sapi Perah)',
        'subtitle': 'Pertumbuhan Rendah, Pangsa Pasar Tinggi',
        'color': AppTheme.accentGreen,
        'bg': AppTheme.lightGreenBg,
        'borderColor': const Color(0xFFA7F3D0),
        'items': provider.getByKategori('Cash Cow'),
      },
      {
        'title': '🐕 DOGS (Anjing)',
        'subtitle': 'Pertumbuhan Rendah, Pangsa Pasar Rendah',
        'color': const Color(0xFFDC2626),
        'bg': const Color(0xFFFEF2F2),
        'borderColor': const Color(0xFFFECACA),
        'items': provider.getByKategori('Dog'),
      },
    ];

    if (isMobile) {
      return Column(
        children: quadrants.map((q) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildQuadrantCard(q),
        )).toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 20) / 2;
        return Wrap(
          spacing: 20,
          runSpacing: 20,
          children: quadrants.map((q) => SizedBox(
            width: cardWidth,
            child: _buildQuadrantCard(q),
          )).toList(),
        );
      },
    );
  }

  Widget _buildQuadrantCard(Map<String, dynamic> q) {
    final List<BCGItem> items = q['items'];
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: q['borderColor'] as Color, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                q['title'] as String,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: q['color'] as Color,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: q['bg'] as Color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${items.length} Unit',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: q['color'] as Color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            q['subtitle'] as String,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Tidak ada unit usaha di kuadran ini', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              ),
            )
          else
            ...items.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item.namaUsaha, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(
                        currency.format(item.arusKas),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildPill('Growth: +${item.growthRate}%'),
                      const SizedBox(width: 6),
                      _buildPill('Market Share: ${item.marketShare}x'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '💡 ${item.rekomendasi}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.3),
                  ),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
    );
  }

  Widget _buildAdviceSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.lightBlueBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.secondaryBlue.withAlpha(50)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_tree_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Kebijakan Alokasi Modal Strategis',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                ),
                SizedBox(height: 6),
                Text(
                  '1. Alihkan 20% kas dari Cash Cow ke Question Mark untuk meningkatkan pangsa pasar sebelum pasar jenuh.\n'
                  '2. Dukung penuh kebutuhan ekspansi Star dari kas internal Star dan surplus Cash Cow.\n'
                  '3. Tinjau unit di kuadran Dog: jika pertumbuhan tidak membaik dalam 2 kuartal, lakukan divestasi aset.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSidebar(BuildContext context) {
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          _buildSidebarItem(context, 'Dashboard', Icons.dashboard_rounded, false, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
          }),
          _buildSidebarItem(context, 'Unit Usaha', Icons.storefront_rounded, false, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UsahaScreen()));
          }),
          _buildSidebarItem(context, 'Transaksi', Icons.receipt_long_rounded, false, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TransaksiScreen()));
          }),
          _buildSidebarItem(context, 'Portofolio BCG', Icons.pie_chart_rounded, true, () {}),
          _buildSidebarItem(context, 'Forecasting', Icons.trending_up_rounded, false, () {}),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(BuildContext context, String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.lightBlueBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary, size: 22),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        onTap: onTap,
      ),
    );
  }

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
            leading: const Icon(Icons.dashboard_rounded),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
            },
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
            leading: const Icon(Icons.pie_chart_rounded, color: AppTheme.primaryBlue),
            title: const Text('Portofolio BCG'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomBar(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 3,
      onTap: (index) {
        if (index == 0) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
        } else if (index == 1) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UsahaScreen()));
        } else if (index == 2) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TransaksiScreen()));
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
