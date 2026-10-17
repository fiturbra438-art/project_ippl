import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/usaha.dart';
import '../providers/usaha_provider.dart';
import '../providers/pos_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_sidebar.dart';
import 'dashboard_screen.dart';
import 'pos_screen.dart';

class UsahaScreen extends StatelessWidget {
  const UsahaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              backgroundColor: AppTheme.surfaceWhite,
              elevation: 0,
              title: const Text(
                'Unit Usaha',
                style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primaryBlue),
                  onPressed: () => _showTambahUsahaDialog(context),
                ),
              ],
            )
          : null,
      drawer: isMobile ? _buildNavigationDrawer(context) : null,
      body: Row(
        children: [
          if (!isMobile) const AppSidebar(activeRoute: 'usaha'),
          Expanded(
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 32,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMobile) _buildDesktopHeader(context),
                    const SizedBox(height: 20),
                    _buildFilterAndSearchBar(context),
                    const SizedBox(height: 20),
                    Expanded(
                      child: _buildUsahaList(context, isMobile),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: isMobile
          ? FloatingActionButton(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              onPressed: () => _showTambahUsahaDialog(context),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: isMobile ? _buildMobileBottomBar(context) : null,
    );
  }

  Widget _buildDesktopHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Kelola Unit Usaha',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Daftar entitas usaha, monitoring profitabilitas, dan klasifikasi BCG.',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: () => _showTambahUsahaDialog(context),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Tambah Unit Usaha'),
        ),
      ],
    );
  }

  Widget _buildFilterAndSearchBar(BuildContext context) {
    final provider = context.watch<UsahaProvider>();
    final categories = ['Semua', 'Star', 'Cash Cow', 'Question Mark', 'Dog'];

    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: provider.setSearchQuery,
            decoration: InputDecoration(
              hintText: 'Cari usaha, jenis, atau lokasi...',
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
              filled: true,
              fillColor: AppTheme.surfaceWhite,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: provider.filterKategori,
              icon: const Icon(Icons.filter_list_rounded, color: AppTheme.primaryBlue),
              items: categories.map((cat) {
                return DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(fontSize: 14)));
              }).toList(),
              onChanged: (val) {
                if (val != null) provider.setFilterKategori(val);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUsahaList(BuildContext context, bool isMobile) {
    final provider = context.watch<UsahaProvider>();
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    if (provider.daftarUsaha.isEmpty) {
      return const Center(
        child: Text('Tidak ada unit usaha yang sesuai pencarian.', style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    if (isMobile) {
      return ListView.separated(
        itemCount: provider.daftarUsaha.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildCardMobile(context, provider.daftarUsaha[index], currency),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 480,
        mainAxisExtent: 250,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: provider.daftarUsaha.length,
      itemBuilder: (context, index) => _buildCardDesktop(context, provider.daftarUsaha[index], currency),
    );
  }

  Widget _buildCardDesktop(BuildContext context, UsahaModel usaha, NumberFormat currency) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.lightBlueBg,
                child: const Icon(Icons.storefront_rounded, color: AppTheme.primaryBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      usaha.nama,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text('${usaha.jenisUsaha} • ${usaha.lokasi}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              _buildTag(usaha.kategoriPortofolio),
            ],
          ),
          const Divider(color: AppTheme.cardBorder),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniMetric('Pendapatan', currency.format(usaha.pendapatanBulanIni), AppTheme.textPrimary),
              _buildMiniMetric('Laba Bersih', currency.format(usaha.labaBersih), AppTheme.accentGreen),
              _buildMiniMetric('Growth', '+${usaha.pertumbuhanPersen}%', AppTheme.primaryBlue),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  context.read<PosProvider>().setActiveUnit(usaha.id, usaha.nama);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen()));
                },
                icon: const Icon(Icons.point_of_sale_rounded, size: 16),
                label: const Text('Buka Kasir POS Unit Ini', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryBlue,
                  side: const BorderSide(color: AppTheme.secondaryBlue),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Hapus Unit Usaha',
                    icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFDC2626)),
                    onPressed: () => _konfirmasiHapusUsaha(context, usaha),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Detail Analitik', style: TextStyle(color: AppTheme.primaryBlue, fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardMobile(BuildContext context, UsahaModel usaha, NumberFormat currency) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  usaha.nama,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ),
              _buildTag(usaha.kategoriPortofolio),
            ],
          ),
          const SizedBox(height: 4),
          Text('${usaha.jenisUsaha} • ${usaha.lokasi}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  context.read<PosProvider>().setActiveUnit(usaha.id, usaha.nama);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen()));
                },
                icon: const Icon(Icons.point_of_sale_rounded, size: 16),
                label: const Text('Buka Kasir', style: TextStyle(fontSize: 12)),
              ),
              IconButton(
                tooltip: 'Hapus Unit Usaha',
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
                onPressed: () => _konfirmasiHapusUsaha(context, usaha),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: valueColor)),
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
    } else if (kategori == 'Question Mark') {
      bg = const Color(0xFFF3E8FF);
      text = const Color(0xFF7E22CE);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        kategori,
        style: TextStyle(color: text, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _konfirmasiHapusUsaha(BuildContext context, UsahaModel usaha) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Text('Konfirmasi Hapus Usaha', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text('Apakah Anda yakin ingin menonaktifkan dan menghapus "${usaha.nama}" dari sistem? Data transaksi historis tetap diarsipkan di Audit Log.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () {
              Provider.of<UsahaProvider>(context, listen: false).hapusUsaha(usaha.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Unit usaha "${usaha.nama}" berhasil dihapus.')),
              );
            },
            child: const Text('Ya, Hapus Usaha'),
          ),
        ],
      ),
    );
  }

  void _showTambahUsahaDialog(BuildContext context) {
    final namaCtrl = TextEditingController();
    final jenisCtrl = TextEditingController();
    final lokasiCtrl = TextEditingController();
    String selectedKategori = 'Star';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Tambah Unit Usaha Baru', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: namaCtrl,
                decoration: const InputDecoration(labelText: 'Nama Usaha', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: jenisCtrl,
                decoration: const InputDecoration(labelText: 'Jenis Usaha (misal: F&B, Jasa)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lokasiCtrl,
                decoration: const InputDecoration(labelText: 'Lokasi', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              if (namaCtrl.text.isNotEmpty) {
                final provider = Provider.of<UsahaProvider>(context, listen: false);
                provider.tambahUsaha(
                  UsahaModel(
                    id: DateTime.now().millisecondsSinceEpoch,
                    nama: namaCtrl.text,
                    jenisUsaha: jenisCtrl.text,
                    lokasi: lokasiCtrl.text,
                    kategoriPortofolio: selectedKategori,
                    pendapatanBulanIni: 0,
                    pengeluaranBulanIni: 0,
                    pertumbuhanPersen: 0,
                  ),
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
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
            leading: const Icon(Icons.storefront_rounded, color: AppTheme.primaryBlue),
            title: const Text('Unit Usaha'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomBar(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 1,
      onTap: (index) {
        if (index == 0) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
        }
      },
      selectedItemColor: AppTheme.primaryBlue,
      unselectedItemColor: AppTheme.textSecondary,
      type: BottomNavigationBarType.fixed,
      backgroundColor: AppTheme.surfaceWhite,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Beranda'),
        BottomNavigationBarItem(icon: Icon(Icons.storefront_rounded), label: 'Usaha'),
      ],
    );
  }
}
