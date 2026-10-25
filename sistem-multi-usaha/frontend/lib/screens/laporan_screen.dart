import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/laporan_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_sidebar.dart';
import 'dashboard_screen.dart';
import 'usaha_screen.dart';
import 'produk_screen.dart';
import 'transaksi_screen.dart';
import 'portofolio_screen.dart';
import 'forecast_screen.dart';
import 'chat_ai_screen.dart';

class LaporanScreen extends StatelessWidget {
  const LaporanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              backgroundColor: AppTheme.surfaceWhite,
              elevation: 0,
              title: const Text('Laporan Finansial', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
              actions: [
                IconButton(icon: const Icon(Icons.download_rounded, color: AppTheme.primaryBlue), onPressed: () {}),
              ],
            )
          : null,
      drawer: isMobile ? _buildNavigationDrawer(context) : null,
      body: Row(
        children: [
          if (!isMobile) const AppSidebar(activeRoute: 'laporan'),
          Expanded(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMobile) _buildDesktopHeader(context),
                    const SizedBox(height: 24),
                    _buildSummaryFinancialCards(context),
                    const SizedBox(height: 28),
                    _buildBreakdownSection(context, isMobile),
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

  Widget _buildDesktopHeader(BuildContext context) {
    final provider = context.watch<LaporanProvider>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Laporan Keuangan & Laba Rugi', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            SizedBox(height: 4),
            Text('Konsolidasi pemasukan, beban operasional, dan kontribusi laba lintas unit.', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          ],
        ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: AppTheme.surfaceWhite, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.cardBorder)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: provider.periodeTerpilih,
                  items: provider.daftarPeriode.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (val) {
                    if (val != null) provider.setPeriode(val);
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Ekspor PDF / Excel'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryFinancialCards(BuildContext context) {
    final provider = context.watch<LaporanProvider>();
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 750;
        final cardWidth = isNarrow ? constraints.maxWidth : (constraints.maxWidth - 32) / 3;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard(
              title: 'Total Pemasukan Konsolidasi',
              value: currency.format(provider.summary.totalPemasukan),
              subtext: 'Seluruh unit aktif',
              color: AppTheme.primaryBlue,
              bg: AppTheme.lightBlueBg,
              icon: Icons.account_balance_wallet_rounded,
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Total Beban & Pengeluaran',
              value: currency.format(provider.summary.totalPengeluaran),
              subtext: 'Bahan baku, gaji & sewa',
              color: const Color(0xFFDC2626),
              bg: const Color(0xFFFEF2F2),
              icon: Icons.money_off_rounded,
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Laba Bersih Operasional',
              value: currency.format(provider.summary.labaOperasional),
              subtext: 'Margin Laba: ${provider.summary.marginLabaPersen}%',
              color: AppTheme.accentGreen,
              bg: AppTheme.lightGreenBg,
              icon: Icons.check_circle_outline_rounded,
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
    required String subtext,
    required Color color,
    required Color bg,
    required IconData icon,
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
              Text(title, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              CircleAvatar(radius: 18, backgroundColor: bg, child: Icon(icon, color: color, size: 18)),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 6),
          Text(subtext, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _buildBreakdownSection(BuildContext context, bool isMobile) {
    final provider = context.watch<LaporanProvider>();
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Kontribusi Laba Bersih per Unit Usaha', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppTheme.surfaceWhite, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.cardBorder)),
          child: Column(
            children: provider.summary.performaUnit.map((unit) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(unit.namaUnit, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('${currency.format(unit.labaBersih)} (${unit.kontribusiPersen}%)', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentGreen, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: unit.kontribusiPersen / 100,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Komposisi Beban Operasional', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppTheme.surfaceWhite, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.cardBorder)),
          child: Column(
            children: provider.summary.rincianPengeluaran.map((kategori) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.circle, size: 10, color: AppTheme.secondaryBlue),
                        const SizedBox(width: 10),
                        Text(kategori.nama, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    Text(
                      '${currency.format(kategori.nominal)} (${kategori.persen}%)',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
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
            leading: const Icon(Icons.assessment_rounded, color: AppTheme.primaryBlue),
            title: const Text('Laporan Keuangan'),
            onTap: () => Navigator.pop(context),
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
        BottomNavigationBarItem(icon: Icon(Icons.assessment_rounded), label: 'Laporan'),
      ],
    );
  }
}
