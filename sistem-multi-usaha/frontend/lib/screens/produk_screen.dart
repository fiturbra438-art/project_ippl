import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/produk.dart';
import '../providers/produk_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_sidebar.dart';
import 'dashboard_screen.dart';
import 'usaha_screen.dart';
import 'transaksi_screen.dart';
import 'portofolio_screen.dart';
import 'forecast_screen.dart';

class ProdukScreen extends StatelessWidget {
  const ProdukScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              backgroundColor: AppTheme.surfaceWhite,
              elevation: 0,
              title: const Text('Inventaris & Produk', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_box_rounded, color: AppTheme.primaryBlue),
                  onPressed: () => _showTambahProdukDialog(context),
                ),
              ],
            )
          : null,
      drawer: isMobile ? _buildNavigationDrawer(context) : null,
      body: Row(
        children: [
          if (!isMobile) const AppSidebar(activeRoute: 'produk'),
          Expanded(
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMobile) _buildDesktopHeader(context),
                    const SizedBox(height: 20),
                    _buildFilterBar(context),
                    const SizedBox(height: 16),
                    Expanded(child: _buildProdukList(context, isMobile)),
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
              onPressed: () => _showTambahProdukDialog(context),
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
            Text('Manajemen Produk & Inventaris', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            SizedBox(height: 4),
            Text('Kontrol stok, batas minimum suplai, dan margin per unit usaha.', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          ],
        ),
        ElevatedButton.icon(
          onPressed: () => _showTambahProdukDialog(context),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Tambah Produk'),
        ),
      ],
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final provider = context.watch<ProdukProvider>();

    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: provider.setSearchQuery,
            decoration: InputDecoration(
              hintText: 'Cari SKU atau nama produk...',
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
              filled: true,
              fillColor: AppTheme.surfaceWhite,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.cardBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: AppTheme.surfaceWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.cardBorder)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: provider.selectedUnitFilter,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Semua Unit Usaha')),
                DropdownMenuItem(value: 1, child: Text('Kedai Kopi Bahagia')),
                DropdownMenuItem(value: 2, child: Text('Laundry Bersih Kilat')),
                DropdownMenuItem(value: 3, child: Text('Toko Elektronik Digital')),
              ],
              onChanged: (val) {
                if (val != null) provider.setUnitFilter(val);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProdukList(BuildContext context, bool isMobile) {
    final provider = context.watch<ProdukProvider>();
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    if (provider.daftarProduk.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 56, color: AppTheme.primaryBlue),
              const SizedBox(height: 16),
              const Text('Katalog Produk Masih Kosong', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              const SizedBox(height: 6),
              const Text(
                'Belum ada barang atau menu yang didaftarkan ke inventaris sistem.\nKlik tombol di bawah untuk menambahkan produk pertama Anda.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => _showTambahProdukDialog(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Tambah Produk Baru'),
              ),
            ],
          ),
        ),
      );
    }

    if (isMobile) {
      return ListView.separated(
        itemCount: provider.daftarProduk.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildCardMobile(context, provider.daftarProduk[index], currency),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListView.separated(
          itemCount: provider.daftarProduk.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.cardBorder),
          itemBuilder: (context, index) {
            final p = provider.daftarProduk[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: p.isStokKritis ? const Color(0xFFFEF2F2) : AppTheme.lightBlueBg,
                    child: Icon(
                      Icons.inventory_2_outlined,
                      color: p.isStokKritis ? const Color(0xFFDC2626) : AppTheme.primaryBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 3),
                        Text('SKU: ${p.sku}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Harga Jual', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        Text(currency.format(p.hargaJual), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Margin Unit', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        Text('+${currency.format(p.marginKeuntungan)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.accentGreen)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: p.isStokKritis ? const Color(0xFFFEF2F2) : AppTheme.lightGreenBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Stok: ${p.stok}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: p.isStokKritis ? const Color(0xFFDC2626) : AppTheme.accentGreen,
                            ),
                          ),
                        ),
                        if (p.isStokKritis) ...[
                          const SizedBox(width: 8),
                          const Text('Kritis!', style: TextStyle(color: Color(0xFFDC2626), fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded, size: 20, color: AppTheme.textSecondary),
                        onPressed: () => context.read<ProdukProvider>().updateStok(p.id, -1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: AppTheme.primaryBlue),
                        onPressed: () => context.read<ProdukProvider>().updateStok(p.id, 1),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCardMobile(BuildContext context, ProdukModel p, NumberFormat currency) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.isStokKritis ? const Color(0xFFFECACA) : AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(p.nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: p.isStokKritis ? const Color(0xFFFEF2F2) : AppTheme.lightGreenBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Stok: ${p.stok}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: p.isStokKritis ? const Color(0xFFDC2626) : AppTheme.accentGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('SKU: ${p.sku}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Harga Jual', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  Text(currency.format(p.hargaJual), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, color: AppTheme.textSecondary),
                    onPressed: () => context.read<ProdukProvider>().updateStok(p.id, -1),
                  ),
                  Text('${p.stok}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primaryBlue),
                    onPressed: () => context.read<ProdukProvider>().updateStok(p.id, 1),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showTambahProdukDialog(BuildContext context) {
    final namaCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    final beliCtrl = TextEditingController();
    final jualCtrl = TextEditingController();
    final stokCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Tambah Produk Inventaris', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: namaCtrl, decoration: const InputDecoration(labelText: 'Nama Produk', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: skuCtrl, decoration: const InputDecoration(labelText: 'Kode SKU', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(controller: beliCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Beli (Rp)', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: jualCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Jual (Rp)', border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 10),
              TextField(controller: stokCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah Stok Awal', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              if (namaCtrl.text.isNotEmpty) {
                Provider.of<ProdukProvider>(context, listen: false).tambahProduk(
                  ProdukModel(
                    id: DateTime.now().millisecondsSinceEpoch,
                    unitId: 1,
                    nama: namaCtrl.text,
                    sku: skuCtrl.text.isEmpty ? 'SKU-001' : skuCtrl.text,
                    hargaBeli: double.tryParse(beliCtrl.text) ?? 0,
                    hargaJual: double.tryParse(jualCtrl.text) ?? 0,
                    stok: int.tryParse(stokCtrl.text) ?? 0,
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

  Widget _buildDesktopSidebar(BuildContext context) {
    return Container(
      width: 250,
      decoration: const BoxDecoration(color: AppTheme.surfaceWhite, border: Border(right: BorderSide(color: AppTheme.cardBorder))),
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
                Text('MultiUsaha', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)),
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
          _buildSidebarItem(context, 'Inventaris', Icons.inventory_2_rounded, true, () {}),
          _buildSidebarItem(context, 'Transaksi', Icons.receipt_long_rounded, false, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TransaksiScreen()));
          }),
          _buildSidebarItem(context, 'Portofolio BCG', Icons.pie_chart_rounded, false, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PortofolioScreen()));
          }),
          _buildSidebarItem(context, 'Forecasting', Icons.trending_up_rounded, false, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ForecastScreen()));
          }),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(BuildContext context, String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: isSelected ? AppTheme.lightBlueBg : Colors.transparent, borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary, size: 22),
        title: Text(label, style: TextStyle(color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 14)),
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
            leading: const Icon(Icons.inventory_2_rounded, color: AppTheme.primaryBlue),
            title: const Text('Inventaris & Produk'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_rounded),
            title: const Text('Transaksi'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TransaksiScreen()));
            },
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
        BottomNavigationBarItem(icon: Icon(Icons.inventory_2_rounded), label: 'Produk'),
        BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'Transaksi'),
        BottomNavigationBarItem(icon: Icon(Icons.pie_chart_rounded), label: 'Portofolio'),
      ],
    );
  }
}
