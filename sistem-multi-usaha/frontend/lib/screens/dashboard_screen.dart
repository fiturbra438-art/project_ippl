import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/notifikasi_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_sidebar.dart';
import 'usaha_screen.dart';
import 'produk_screen.dart';
import 'pos_screen.dart';
import 'gudang_screen.dart';
import 'transaksi_screen.dart';
import 'laporan_screen.dart';
import 'permintaan_stok_screen.dart';
import 'portofolio_screen.dart';
import 'forecast_screen.dart';
import 'ai_hub_screen.dart';
import 'chat_ai_screen.dart';
import 'user_management_screen.dart';
import 'notifikasi_screen.dart';
import 'login_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final auth = context.watch<AuthProvider>();
    final notif = context.watch<NotifikasiProvider>();

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              backgroundColor: AppTheme.surfaceWhite,
              elevation: 0,
              centerTitle: false,
              title: Text(
                'MultiUsaha (${auth.currentUser?.role.label ?? "Owner"})',
                style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              actions: [
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.textPrimary),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotifikasiScreen())),
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
                _buildRoleSwitcher(context),
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
                    _buildQuickActionCards(context),
                    const SizedBox(height: 24),
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

  Widget _buildDesktopTopBar(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final notif = context.watch<NotifikasiProvider>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Dashboard ${auth.currentUser?.role.label ?? "Owner"}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                ),
                const SizedBox(width: 12),
                _buildRoleTag(auth.currentUser?.role ?? UserRole.owner),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Pantau performa finansial, stok, POS, dan intelijen AI seluruh unit usaha.',
              style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ],
        ),
        Row(
          children: [
            // Unit Selector
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: AppTheme.surfaceWhite, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.cardBorder)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: auth.selectedUnitId,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('🏢 Konsolidasi Semua Unit')),
                    DropdownMenuItem(value: 1, child: Text('☕ Kedai Kopi Bahagia')),
                    DropdownMenuItem(value: 2, child: Text('🧺 Laundry Bersih Kilat')),
                    DropdownMenuItem(value: 3, child: Text('📱 Toko Elektronik Digital')),
                  ],
                  onChanged: (val) => auth.setSelectedUnit(val),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Switch Role (Simulator Hak Akses)
            _buildRoleSwitcher(context),
            const SizedBox(width: 12),
            Stack(
              alignment: Alignment.topRight,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.primaryBlue),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotifikasiScreen())),
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

  Widget _buildRoleSwitcher(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: AppTheme.lightBlueBg, borderRadius: BorderRadius.circular(10)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<UserRole>(
          value: auth.currentUser?.role ?? UserRole.owner,
          items: UserRole.values.map((r) {
            return DropdownMenuItem(value: r, child: Text('Peran: ${r.label}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)));
          }).toList(),
          onChanged: (role) {
            if (role != null) auth.switchRoleForPreview(role);
          },
        ),
      ),
    );
  }

  Widget _buildRoleTag(UserRole role) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppTheme.lightGreenBg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        'Hak Akses: ${role.label}',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentGreen),
      ),
    );
  }

  // Quick Action Shortcut Tiles
  Widget _buildQuickActionCards(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = auth.currentUser?.role ?? UserRole.owner;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        if (role == UserRole.owner || role == UserRole.kasir)
          _buildActionChip(context, Icons.point_of_sale_rounded, 'Buka Mesin Kasir (POS)', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen()));
          }),
        if (role == UserRole.owner || role == UserRole.adminGudang)
          _buildActionChip(context, Icons.warehouse_rounded, 'Transfer & Opname Gudang', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const GudangScreen()));
          }),
        if (role == UserRole.owner || role == UserRole.manager)
          _buildActionChip(context, Icons.add_shopping_cart_rounded, 'Pengajuan Stok (Manager)', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PermintaanStokScreen()));
          }),
        if (role == UserRole.owner)
          _buildActionChip(context, Icons.auto_awesome_rounded, 'AI Intelligence Suite', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AiHubScreen()));
          }),
        if (role == UserRole.owner || role == UserRole.auditor)
          _buildActionChip(context, Icons.manage_accounts_rounded, 'Kelola Pengguna & Audit', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
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

  // Finansial Metrics
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
              title: 'Total Omzet Terkonsolidasi',
              value: currency.format(provider.totalPendapatan),
              badgeText: '+14.2% bln ini',
              isBadgePositive: true,
              icon: Icons.trending_up_rounded,
              iconColor: AppTheme.primaryBlue,
              iconBg: AppTheme.lightBlueBg,
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Total Arus Kas Keluar',
              value: currency.format(provider.totalPengeluaran),
              badgeText: 'Terkendali',
              isBadgePositive: true,
              icon: Icons.account_balance_wallet_outlined,
              iconColor: AppTheme.textSecondary,
              iconBg: const Color(0xFFF1F5F9),
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Laba Bersih Operasional',
              value: currency.format(provider.totalLabaBersih),
              badgeText: '+26.2% margin',
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

  // Business Units List
  Widget _buildBusinessUnitsSection(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Unit Usaha Aktif & Klasifikasi BCG', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsahaScreen())),
              child: const Text('Kelola Unit', style: TextStyle(color: AppTheme.primaryBlue)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: provider.daftarUsaha.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final usaha = provider.daftarUsaha[index];
            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: AppTheme.surfaceWhite, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.cardBorder)),
              child: Row(
                children: [
                  CircleAvatar(radius: 22, backgroundColor: AppTheme.lightBlueBg, child: const Icon(Icons.storefront_rounded, color: AppTheme.primaryBlue, size: 24)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(usaha.nama, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                            const SizedBox(width: 8),
                            _buildTag(usaha.kategoriPortofolio),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('${usaha.jenisUsaha} • ${usaha.lokasi}', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(currency.format(usaha.pendapatanBulanIni), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 2),
                      Text('+${usaha.pertumbuhanPersen}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentGreen)),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(kategori, style: TextStyle(color: text, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  // AI Alokasi Kas Card
  Widget _buildAllocationRecommendationCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E40AF), Color(0xFF2563EB)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withAlpha(38), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28)),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Rekomendasi Realokasi Stok & Modal AI', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('AI menemukan surplus kas pada unit Cash Cow dan peluang realokasi stok fast-moving untuk mencegah stockout.', style: TextStyle(color: Color(0xFFDBEAFE), fontSize: 13, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiHubScreen())),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGreen, foregroundColor: Colors.white),
            child: const Text('Buka AI Suite'),
          ),
        ],
      ),
    );
  }

  // Sidebar Desktop
  Widget _buildDesktopSidebar(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = auth.currentUser?.role ?? UserRole.owner;

    return Container(
      width: 250,
      decoration: const BoxDecoration(color: AppTheme.surfaceWhite, border: Border(right: BorderSide(color: AppTheme.cardBorder))),
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
                Text('MultiUsaha', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildSidebarItem(context, 'Dashboard', Icons.dashboard_rounded, true, () {}),
                if (role == UserRole.owner || role == UserRole.manager)
                  _buildSidebarItem(context, 'Kelola Unit', Icons.storefront_rounded, false, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const UsahaScreen()));
                  }),
                if (role == UserRole.owner || role == UserRole.kasir)
                  _buildSidebarItem(context, 'Kasir (POS)', Icons.point_of_sale_rounded, false, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen()));
                  }),
                if (role == UserRole.owner || role == UserRole.adminGudang)
                  _buildSidebarItem(context, 'Gudang & Stok', Icons.warehouse_rounded, false, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const GudangScreen()));
                  }),
                if (role == UserRole.owner || role == UserRole.adminGudang || role == UserRole.manager)
                  _buildSidebarItem(context, 'Katalog Produk', Icons.inventory_2_rounded, false, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProdukScreen()));
                  }),
                if (role == UserRole.owner || role == UserRole.manager)
                  _buildSidebarItem(context, 'Permintaan Stok', Icons.add_shopping_cart_rounded, false, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PermintaanStokScreen()));
                  }),
                if (role == UserRole.owner || role == UserRole.kasir || role == UserRole.manager)
                  _buildSidebarItem(context, 'Transaksi Kas', Icons.receipt_long_rounded, false, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TransaksiScreen()));
                  }),
                if (role == UserRole.owner || role == UserRole.manager || role == UserRole.auditor)
                  _buildSidebarItem(context, 'Laporan Unit', Icons.assessment_rounded, false, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const LaporanScreen()));
                  }),
                if (role == UserRole.owner) ...[
                  const Divider(color: AppTheme.cardBorder),
                  _buildSidebarItem(context, 'AI Intelligence Suite', Icons.auto_awesome_rounded, false, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AiHubScreen()));
                  }),
                  _buildSidebarItem(context, 'Portofolio BCG', Icons.pie_chart_rounded, false, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PortofolioScreen()));
                  }),
                  _buildSidebarItem(context, 'Forecasting AI', Icons.trending_up_rounded, false, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ForecastScreen()));
                  }),
                  _buildSidebarItem(context, 'Chatbot BI', Icons.smart_toy_rounded, false, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatAiScreen()));
                  }),
                  _buildSidebarItem(context, 'Kelola Pengguna', Icons.manage_accounts_rounded, false, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
                  }),
                ],
              ],
            ),
          ),
          const Divider(color: AppTheme.cardBorder),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.lightBlueBg,
              child: Text(auth.currentUser?.nama.isNotEmpty == true ? auth.currentUser!.nama[0] : 'U', style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
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

  Widget _buildSidebarItem(BuildContext context, String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: BoxDecoration(color: isSelected ? AppTheme.lightBlueBg : Colors.transparent, borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        visualDensity: const VisualDensity(vertical: -3),
        leading: Icon(icon, color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary, size: 20),
        title: Text(label, style: TextStyle(color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
        onTap: onTap,
      ),
    );
  }

  // Drawer Mobile
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
                Text('User: ${auth.currentUser?.nama} (${auth.currentUser?.role.label})', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          ListTile(leading: const Icon(Icons.dashboard_rounded, color: AppTheme.primaryBlue), title: const Text('Dashboard'), onTap: () => Navigator.pop(context)),
          ListTile(leading: const Icon(Icons.point_of_sale_rounded), title: const Text('Kasir POS'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen()))),
          ListTile(leading: const Icon(Icons.warehouse_rounded), title: const Text('Gudang & Transfer'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GudangScreen()))),
          ListTile(leading: const Icon(Icons.auto_awesome_rounded), title: const Text('AI Suite (Owner)'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiHubScreen()))),
          ListTile(leading: const Icon(Icons.smart_toy_rounded), title: const Text('Chatbot BI AI'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatAiScreen()))),
          ListTile(leading: const Icon(Icons.people_outline_rounded), title: const Text('Pengguna & Audit'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()))),
        ],
      ),
    );
  }

  // Mobile Bottom Bar
  Widget _buildMobileBottomBar(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 0,
      onTap: (index) {
        if (index == 1) Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen()));
        if (index == 2) Navigator.push(context, MaterialPageRoute(builder: (_) => const GudangScreen()));
        if (index == 3) Navigator.push(context, MaterialPageRoute(builder: (_) => const AiHubScreen()));
      },
      selectedItemColor: AppTheme.primaryBlue,
      unselectedItemColor: AppTheme.textSecondary,
      type: BottomNavigationBarType.fixed,
      backgroundColor: AppTheme.surfaceWhite,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Beranda'),
        BottomNavigationBarItem(icon: Icon(Icons.point_of_sale_rounded), label: 'Kasir'),
        BottomNavigationBarItem(icon: Icon(Icons.warehouse_rounded), label: 'Gudang'),
        BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_rounded), label: 'AI Suite'),
      ],
    );
  }
}
