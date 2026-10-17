import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/transaksi.dart';
import '../providers/transaksi_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import 'dashboard_screen.dart';
import 'usaha_screen.dart';

class TransaksiScreen extends StatelessWidget {
  const TransaksiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              backgroundColor: AppTheme.surfaceWhite,
              elevation: 0,
              title: const Text(
                'Transaksi',
                style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primaryBlue),
                  onPressed: () => _showTambahTransaksiDialog(context),
                ),
              ],
            )
          : null,
      drawer: isMobile ? _buildNavigationDrawer(context) : null,
      body: Row(
        children: [
          if (!isMobile) _buildDesktopSidebar(context),
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
                    _buildFilterTabs(context),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _buildTransactionList(context),
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
              onPressed: () => _showTambahTransaksiDialog(context),
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
              'Riwayat Transaksi Arus Kas',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
            ),
            SizedBox(height: 4),
            Text(
              'Pencatatan pemasukan dan pengeluaran lintas unit usaha.',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: () => _showTambahTransaksiDialog(context),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Catat Transaksi'),
        ),
      ],
    );
  }

  Widget _buildFilterTabs(BuildContext context) {
    final provider = context.watch<TransaksiProvider>();
    final filters = ['Semua', 'Pemasukan', 'Pengeluaran'];

    return Row(
      children: filters.map((tab) {
        final isSelected = provider.filterJenis == tab;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(tab),
            selected: isSelected,
            selectedColor: AppTheme.primaryBlue,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            backgroundColor: AppTheme.surfaceWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (_) => provider.setFilterJenis(tab),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTransactionList(BuildContext context) {
    final provider = context.watch<TransaksiProvider>();
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    if (provider.daftarTransaksi.isEmpty) {
      return const Center(child: Text('Belum ada transaksi pada kategori ini.', style: TextStyle(color: AppTheme.textSecondary)));
    }

    return ListView.separated(
      itemCount: provider.daftarTransaksi.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = provider.daftarTransaksi[index];
        final isIncome = item.jenis == JenisTransaksi.pemasukan;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isIncome ? AppTheme.lightGreenBg : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                  color: isIncome ? AppTheme.accentGreen : const Color(0xFFEF4444),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.kategori,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item.namaUnit} • ${dateFormat.format(item.tanggal)}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Text(
                '${isIncome ? '+' : '-'}${currency.format(item.jumlah)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isIncome ? AppTheme.accentGreen : const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTambahTransaksiDialog(BuildContext context) {
    final jumlahCtrl = TextEditingController();
    final kategoriCtrl = TextEditingController();
    JenisTransaksi jenis = JenisTransaksi.pemasukan;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Catat Transaksi Kas', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<JenisTransaksi>(
                      title: const Text('Masuk'),
                      value: JenisTransaksi.pemasukan,
                      groupValue: jenis,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => setState(() => jenis = val!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<JenisTransaksi>(
                      title: const Text('Keluar'),
                      value: JenisTransaksi.pengeluaran,
                      groupValue: jenis,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => setState(() => jenis = val!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: kategoriCtrl,
                decoration: const InputDecoration(labelText: 'Kategori / Keterangan', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: jumlahCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nominal (Rp)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () {
                final nominal = double.tryParse(jumlahCtrl.text) ?? 0;
                if (nominal > 0) {
                  Provider.of<TransaksiProvider>(context, listen: false).tambahTransaksi(
                    TransaksiModel(
                      id: DateTime.now().millisecondsSinceEpoch,
                      unitId: 1,
                      namaUnit: 'Kedai Kopi Bahagia',
                      tanggal: DateTime.now(),
                      jenis: jenis,
                      kategori: kategoriCtrl.text.isEmpty ? 'Umum' : kategoriCtrl.text,
                      jumlah: nominal,
                      keterangan: '',
                    ),
                  );
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
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
          _buildSidebarItem(context, 'Transaksi', Icons.receipt_long_rounded, true, () {}),
          _buildSidebarItem(context, 'Portofolio BCG', Icons.pie_chart_rounded, false, () {}),
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
            leading: const Icon(Icons.receipt_long_rounded, color: AppTheme.primaryBlue),
            title: const Text('Transaksi'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomBar(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 2,
      onTap: (index) {
        if (index == 0) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
        } else if (index == 1) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UsahaScreen()));
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
