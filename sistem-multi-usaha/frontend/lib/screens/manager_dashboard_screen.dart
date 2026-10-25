import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/notifikasi_provider.dart';
import '../providers/pos_provider.dart';
import '../providers/produk_provider.dart';
import '../providers/transaksi_provider.dart';
import '../providers/usaha_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_navigator.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_sidebar.dart';
import 'gudang_screen.dart';
import 'laporan_screen.dart';
import 'login_screen.dart';
import 'notifikasi_screen.dart';
import 'permintaan_stok_screen.dart';
import 'pos_screen.dart';
import 'produk_screen.dart';
import 'transaksi_screen.dart';

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final notif = context.watch<NotifikasiProvider>();

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: isMobile
          ? AppBar(
              title: const Text('Dashboard Operasional Cabang', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              backgroundColor: AppTheme.surfaceWhite,
              elevation: 0,
              actions: [
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.textPrimary),
                      onPressed: () => AppNavigator.pushFullscreen(context, const NotifikasiScreen()),
                    ),
                    if (notif.unreadCount > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 8, right: 8),
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle),
                        child: Text('${notif.unreadCount}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ],
            )
          : null,
      drawer: isMobile ? _buildNavigationDrawer(context) : null,
      body: Row(
        children: [
          if (!isMobile) const AppSidebar(activeRoute: 'dashboard'),
          Expanded(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMobile) _buildDesktopTopBar(context),
                    if (!isMobile) const SizedBox(height: 24),
                    _buildBranchStatusBanner(context),
                    const SizedBox(height: 24),
                    _buildQuickActionCards(context),
                    const SizedBox(height: 24),
                    _buildOperationalMetrics(context),
                    const SizedBox(height: 32),
                    _buildBranchInventoryAlert(context),
                    const SizedBox(height: 32),
                    _buildRecentTransactions(context),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTopBar(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final notif = context.watch<NotifikasiProvider>();
    final usahaProv = context.watch<UsahaProvider>();

    final userUnits = usahaProv.getDaftarUsahaForUser(auth.currentUser?.unitAksesIds ?? [], false);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Dashboard Manajer Cabang',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppTheme.lightBlueBg, borderRadius: BorderRadius.circular(6)),
                  child: const Text(
                    'Peran: Manajer Operasional',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Kendali shift kasir, ketersediaan inventaris, dan alur transaksi cabang Anda.',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ],
        ),
        Row(
          children: [
            if (userUnits.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceWhite,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: auth.selectedUnitId ?? (userUnits.isNotEmpty ? userUnits.first.id : null),
                    items: userUnits.map((u) {
                      return DropdownMenuItem<int?>(value: u.id, child: Text('📍 ${u.nama}'));
                    }).toList(),
                    onChanged: (val) => auth.setSelectedUnit(val),
                  ),
                ),
              ),
            const SizedBox(width: 12),
            Stack(
              alignment: Alignment.topRight,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.primaryBlue),
                  onPressed: () => AppNavigator.pushFullscreen(context, const NotifikasiScreen()),
                ),
                if (notif.unreadCount > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 4, right: 4),
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle),
                    child: Text('${notif.unreadCount}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBranchStatusBanner(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final isShiftOpen = pos.shiftIsOpen;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isShiftOpen ? AppTheme.lightGreenBg : const Color(0xFFFEF2F2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isShiftOpen ? Icons.storefront_rounded : Icons.store_mall_directory_outlined,
              color: isShiftOpen ? AppTheme.accentGreen : const Color(0xFFEF4444),
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isShiftOpen ? 'Operasional Kasir: AKTIF' : 'Operasional Kasir: BELUM DIBUKA',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isShiftOpen ? AppTheme.accentGreen : const Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isShiftOpen
                      ? 'Shift kasir di unit ${pos.activeUnitNama} sedang aktif.'
                      : 'Belum ada shift kasir aktif yang dibuka pada unit ini.',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => AppNavigator.pushFullscreen(context, const PosScreen()),
            icon: const Icon(Icons.point_of_sale_rounded, size: 16),
            label: Text(isShiftOpen ? 'Buka Mesin POS' : 'Buka Shift POS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCards(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildActionChip(context, Icons.point_of_sale_rounded, 'Kasir Cabang (POS)', () {
          AppNavigator.pushFullscreen(context, const PosScreen());
        }),
        _buildActionChip(context, Icons.add_shopping_cart_rounded, 'Ajukan Permintaan Stok', () {
          AppNavigator.pushFullscreen(context, const PermintaanStokScreen());
        }),
        _buildActionChip(context, Icons.warehouse_rounded, 'Cek Gudang & Mutasi', () {
          AppNavigator.pushFullscreen(context, const GudangScreen());
        }),
        _buildActionChip(context, Icons.inventory_2_rounded, 'Katalog Produk Cabang', () {
          AppNavigator.pushFullscreen(context, const ProdukScreen());
        }),
        _buildActionChip(context, Icons.receipt_long_rounded, 'Catat Arus Kas Operasional', () {
          AppNavigator.pushFullscreen(context, const TransaksiScreen());
        }),
        _buildActionChip(context, Icons.assessment_rounded, 'Laporan Penjualan Cabang', () {
          AppNavigator.pushFullscreen(context, const LaporanScreen());
        }),
      ],
    );
  }

  Widget _buildActionChip(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppTheme.primaryBlue),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textPrimary)),
      backgroundColor: AppTheme.surfaceWhite,
      side: const BorderSide(color: AppTheme.cardBorder),
      onPressed: onTap,
    );
  }

  Widget _buildOperationalMetrics(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final usahaProv = context.watch<UsahaProvider>();
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    final unitList = usahaProv.getDaftarUsahaForUser(auth.currentUser?.unitAksesIds ?? [], false);
    final totalPendapatan = unitList.fold(0.0, (sum, u) => sum + u.pendapatanBulanIni);
    final totalPengeluaran = unitList.fold(0.0, (sum, u) => sum + u.pengeluaranBulanIni);
    final labaOperasional = totalPendapatan - totalPengeluaran;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;
        final cardWidth = isNarrow ? constraints.maxWidth : (constraints.maxWidth - 32) / 3;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard(
              title: 'Omzet Penjualan Cabang',
              value: currency.format(totalPendapatan),
              badgeText: 'Bulan Ini',
              isBadgePositive: true,
              icon: Icons.payments_rounded,
              iconColor: AppTheme.primaryBlue,
              iconBg: AppTheme.lightBlueBg,
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Biaya Operasional Cabang',
              value: currency.format(totalPengeluaran),
              badgeText: 'Pengeluaran',
              isBadgePositive: false,
              icon: Icons.receipt_long_rounded,
              iconColor: AppTheme.textSecondary,
              iconBg: const Color(0xFFF1F5F9),
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Laba Bersih Cabang',
              value: currency.format(labaOperasional),
              badgeText: labaOperasional >= 0 ? 'Surplus' : 'Defisit',
              isBadgePositive: labaOperasional >= 0,
              icon: Icons.account_balance_wallet_rounded,
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
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: iconColor, size: 22)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: isBadgePositive ? AppTheme.lightGreenBg : const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(20)),
                child: Text(badgeText, style: TextStyle(color: isBadgePositive ? AppTheme.accentGreen : const Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildBranchInventoryAlert(BuildContext context) {
    final produkProv = context.watch<ProdukProvider>();
    final auth = context.watch<AuthProvider>();
    final userUnitIds = auth.currentUser?.unitAksesIds ?? [];

    final produkKritis = produkProv.daftarProduk
        .where((p) => p.stok <= p.minStok && (userUnitIds.isEmpty || userUnitIds.contains(p.unitId)))
        .toList();

    return Container(
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
              Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
                  SizedBox(width: 8),
                  Text('Peringatan Stok Kritis Cabang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                ],
              ),
              TextButton(
                onPressed: () => AppNavigator.pushFullscreen(context, const PermintaanStokScreen()),
                child: const Text('Buat Permintaan Stok'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (produkKritis.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Seluruh stok produk cabang dalam batas aman.', style: TextStyle(color: AppTheme.accentGreen)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: produkKritis.take(4).length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final p = produkKritis[index];
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('SKU: ${p.sku}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8)),
                      child: Text('Sisa ${p.stok} (Min: ${p.minStok})', style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions(BuildContext context) {
    final trxProv = context.watch<TransaksiProvider>();
    final auth = context.watch<AuthProvider>();
    final userUnitIds = auth.currentUser?.unitAksesIds ?? [];
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    final recentTrxs = trxProv.daftarTransaksi
        .where((t) => userUnitIds.isEmpty || userUnitIds.contains(t.unitId))
        .take(5)
        .toList();

    return Container(
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
              const Text('Transaksi Kasir Terakhir Cabang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              TextButton(
                onPressed: () => AppNavigator.pushFullscreen(context, const TransaksiScreen()),
                child: const Text('Lihat Semua Transaksi'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recentTrxs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Belum ada transaksi di cabang ini.', style: TextStyle(color: AppTheme.textSecondary)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentTrxs.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final t = recentTrxs[index];
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.keterangan.isNotEmpty ? t.keterangan : 'Transaksi #${t.id}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text('${DateFormat('dd/MM/yyyy HH:mm').format(t.tanggal)} • ${t.kategori}', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                      ],
                    ),
                    Text(currency.format(t.jumlah), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.accentGreen)),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildNavigationDrawer(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: AppTheme.primaryBlue),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('MultiUsaha', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Manajer: ${auth.currentUser?.nama}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          ListTile(leading: const Icon(Icons.dashboard_rounded, color: AppTheme.primaryBlue), title: const Text('Dashboard Cabang'), onTap: () => Navigator.pop(context)),
          ListTile(leading: const Icon(Icons.point_of_sale_rounded), title: const Text('Kasir (POS)'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen()))),
          ListTile(leading: const Icon(Icons.warehouse_rounded), title: const Text('Gudang & Mutasi'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GudangScreen()))),
          ListTile(leading: const Icon(Icons.add_shopping_cart_rounded), title: const Text('Permintaan Stok'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PermintaanStokScreen()))),
          ListTile(leading: const Icon(Icons.inventory_2_rounded), title: const Text('Katalog Produk'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProdukScreen()))),
          ListTile(leading: const Icon(Icons.assessment_rounded), title: const Text('Laporan Cabang'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LaporanScreen()))),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
            title: const Text('Keluar Akun', style: TextStyle(color: Color(0xFFEF4444))),
            onTap: () {
              auth.logout();
              AppNavigator.pushReplacementFullscreen(context, const LoginScreen());
            },
          ),
        ],
      ),
    );
  }
}
