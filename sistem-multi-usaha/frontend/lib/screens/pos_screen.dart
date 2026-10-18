import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/produk.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/pos_provider.dart';
import '../providers/produk_provider.dart';
import '../providers/usaha_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_navigator.dart';
import 'dashboard_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final pos = context.watch<PosProvider>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => AppNavigator.backToDashboard(context, const DashboardScreen()),
        ),
        title: Row(
          children: [
            const Text('Mesin Kasir (POS)', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.lightBlueBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.secondaryBlue.withAlpha(50)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: pos.activeUnitId,
                  items: () {
                    final auth = context.watch<AuthProvider>();
                    final usahaProv = context.watch<UsahaProvider>();
                    final currentUser = auth.currentUser;
                    final isOwnerOrAuditor = currentUser?.role == UserRole.owner || currentUser?.role == UserRole.auditor;
                    final unitAkses = currentUser?.unitAksesIds ?? [];

                    return usahaProv
                        .getDaftarUsahaForUser(unitAkses, isOwnerOrAuditor)
                        .where((u) => u.hasPos) // Hanya unit yang boleh diakses karyawan & punya kasir
                        .map((u) {
                      return DropdownMenuItem<int>(
                        value: u.id,
                        child: Text('📍 ${u.nama}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                      );
                    }).toList();
                  }(),
                  onChanged: (val) {
                    if (val != null) {
                      final selected = context.read<UsahaProvider>().daftarUsaha.firstWhere((u) => u.id == val);
                      pos.setActiveUnit(val, selected.nama);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: pos.isOfflineMode ? const Color(0xFFFEF2F2) : AppTheme.lightGreenBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: pos.isOfflineMode ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0)),
              ),
              child: Row(
                children: [
                  Icon(
                    pos.isOfflineMode ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                    size: 14,
                    color: pos.isOfflineMode ? const Color(0xFFDC2626) : AppTheme.accentGreen,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    pos.isOfflineMode
                        ? 'Mode Offline (${pos.offlineQueueCount} tertunda)'
                        : 'Online (Tersinkron)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: pos.isOfflineMode ? const Color(0xFFDC2626) : AppTheme.accentGreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Simulasi Putus/Sambung Internet',
            icon: Icon(
              pos.isOfflineMode ? Icons.wifi_off_rounded : Icons.wifi_rounded,
              color: pos.isOfflineMode ? const Color(0xFFDC2626) : AppTheme.primaryBlue,
            ),
            onPressed: () => pos.toggleOfflineMode(),
          ),
          ElevatedButton.icon(
            onPressed: () => _showTutupShiftDialog(context),
            icon: const Icon(Icons.lock_clock_rounded, size: 16),
            label: const Text('Tutup Shift'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: isMobile ? _buildMobileView(context) : _buildDesktopView(context),
    );
  }

  Widget _buildDesktopView(BuildContext context) {
    return Row(
      children: [
        // Panel Katalog Produk (Kiri)
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSearchBar(),
                const SizedBox(height: 16),
                Expanded(child: _buildProductCatalog()),
              ],
            ),
          ),
        ),
        // Panel Keranjang & Pembayaran (Kanan)
        Expanded(
          flex: 4,
          child: Container(
            decoration: const BoxDecoration(
              color: AppTheme.surfaceWhite,
              border: Border(left: BorderSide(color: AppTheme.cardBorder)),
            ),
            child: _buildCartPanel(context),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileView(BuildContext context) {
    final pos = context.watch<PosProvider>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: _buildSearchBar(),
        ),
        Expanded(child: _buildProductCatalog()),
        if (pos.keranjang.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceWhite,
              border: Border(top: BorderSide(color: AppTheme.cardBorder)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${pos.keranjang.length} Produk Dipilih', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    Text(currency.format(pos.grandTotal), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                  ],
                ),
                ElevatedButton(
                  onPressed: () => _showMobileCartBottomSheet(context),
                  child: const Text('Lihat Keranjang & Bayar'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            onChanged: (val) => context.read<ProdukProvider>().setSearchQuery(val),
            decoration: InputDecoration(
              hintText: 'Cari nama produk atau ketik SKU...',
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
              filled: true,
              fillColor: AppTheme.surfaceWhite,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.cardBorder)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'Simulasi Scan Barcode Scanner',
          icon: const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.primaryBlue),
          onPressed: () {
            // Simulasi scan barcode otomatis tambah produk pertama
            final produkList = context.read<ProdukProvider>().daftarProduk;
            if (produkList.isNotEmpty) {
              context.read<PosProvider>().tambahKeKeranjang(produkList.first);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Barcode discan: ${produkList.first.nama}')),
              );
            }
          },
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: () => _showTambahBarangDialog(context),
          icon: Icon(
            context.watch<AuthProvider>().canManagePrices
                ? Icons.add_rounded
                : Icons.lock_outline_rounded,
            size: 18,
          ),
          label: Text(
            context.watch<AuthProvider>().canManagePrices
                ? 'Tambah Barang (Manager)'
                : 'Tambah Barang',
            style: const TextStyle(fontSize: 13),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: context.watch<AuthProvider>().canManagePrices
                ? AppTheme.primaryBlue
                : const Color(0xFF64748B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildProductCatalog() {
    final produkList = context.watch<ProdukProvider>().daftarProduk;

    if (produkList.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.point_of_sale_rounded, size: 48, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              const Text('Katalog Kasir Masih Kosong', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('Tambahkan barang jualan atau menu pertama Anda melalui tombol di atas.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () => _showTambahBarangDialog(context),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Tambah Menu Sekarang'),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 170,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: produkList.length,
      itemBuilder: (context, index) {
        final item = produkList[index];
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.read<PosProvider>().tambahKeKeranjang(item),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppTheme.lightBlueBg,
                      child: const Icon(Icons.inventory_2_rounded, size: 16, color: AppTheme.primaryBlue),
                    ),
                    Text('Stok: ${item.stok}', style: TextStyle(fontSize: 11, color: item.isStokKritis ? const Color(0xFFDC2626) : AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nama, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(item.sku, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
                Text(currency.format(item.hargaJual), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCartPanel(BuildContext context) {
    final pos = context.watch<PosProvider>();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Pesanan Pelanggan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('${pos.keranjang.length} item', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ],
          ),
          const Divider(height: 20, color: AppTheme.cardBorder),
          Expanded(
            child: pos.keranjang.isEmpty
                ? const Center(child: Text('Keranjang kosong. Klik produk di sebelah kiri.', style: TextStyle(color: AppTheme.textMuted)))
                : ListView.separated(
                    itemCount: pos.keranjang.length,
                    separatorBuilder: (_, __) => const Divider(height: 12, color: AppTheme.cardBorder),
                    itemBuilder: (context, index) {
                      final c = pos.keranjang[index];
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.produk.nama, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text(currency.format(c.produk.hargaJual), style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, size: 18, color: AppTheme.textSecondary),
                                onPressed: () => pos.ubahKuantitas(c.produk.id, -1),
                              ),
                              Text('${c.kuantitas}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, size: 18, color: AppTheme.primaryBlue),
                                onPressed: () => pos.ubahKuantitas(c.produk.id, 1),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Text(currency.format(c.subtotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      );
                    },
                  ),
          ),
          const Divider(height: 20, color: AppTheme.cardBorder),
          // Diskon dan Metode Pembayaran
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Diskon Promo', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              Row(
                children: [0, 5, 10].map((d) {
                  final isSelected = pos.diskonPersen == d.toDouble();
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ChoiceChip(
                      label: Text('$d%'),
                      selected: isSelected,
                      selectedColor: AppTheme.lightBlueBg,
                      labelStyle: TextStyle(fontSize: 11, color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary, fontWeight: FontWeight.bold),
                      onSelected: (_) => pos.setDiskon(d.toDouble()),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Metode Bayar', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              DropdownButton<MetodeBayar>(
                value: pos.metodeBayar,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: MetodeBayar.qris, child: Text('QRIS Digital', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: MetodeBayar.tunai, child: Text('Uang Tunai', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: MetodeBayar.transferBank, child: Text('Transfer Bank', style: TextStyle(fontSize: 13))),
                ],
                onChanged: (val) {
                  if (val != null) pos.setMetodeBayar(val);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Pembayaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(currency.format(pos.grandTotal), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.primaryBlue)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: pos.keranjang.isEmpty ? null : () => _showStrukDialog(context),
              icon: const Icon(Icons.print_rounded, size: 20),
              label: const Text('Proses Bayar & Cetak Struk', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _showMobileCartBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: _buildCartPanel(context),
      ),
    );
  }

  void _showStrukDialog(BuildContext context) {
    final pos = Provider.of<PosProvider>(context, listen: false);
    final total = pos.grandTotal;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.receipt_long_rounded, color: AppTheme.accentGreen),
            SizedBox(width: 8),
            Text('Struk Pembayaran Sukses', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('KEDAI KOPI & MULTI USAHA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Text('Jl. Merdeka No. 12 • Telp: 08123456789', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Transaksi', style: TextStyle(fontSize: 13)),
                  Text(currency.format(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Metode', style: TextStyle(fontSize: 13)),
                  Text(pos.metodeBayar.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const Divider(height: 20),
              const Text('Struk dapat dikirim via printer thermal 58/80mm atau digital PDF/WhatsApp.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              pos.checkoutBerhasil();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Struk digital dikirim via WhatsApp')));
            },
            icon: const Icon(Icons.share_rounded, size: 16),
            label: const Text('Kirim Digital'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              pos.checkoutBerhasil();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mencetak struk ke printer thermal...')));
            },
            icon: const Icon(Icons.print_rounded, size: 16),
            label: const Text('Cetak Thermal'),
          ),
        ],
      ),
    );
  }

  void _showTutupShiftDialog(BuildContext context) {
    final pos = Provider.of<PosProvider>(context, listen: false);
    final uangFisikCtrl = TextEditingController(text: '${pos.modalAwal + pos.totalPenjualanShift}');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final fisik = double.tryParse(uangFisikCtrl.text) ?? 0;
          final tercatatSistem = pos.modalAwal + pos.totalPenjualanShift;
          final selisih = fisik - tercatatSistem;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Rekap Tutup Shift Kasir', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kas Modal Awal: ${currency.format(pos.modalAwal)}', style: const TextStyle(fontSize: 13)),
                  Text('Penjualan Shift Ini: ${currency.format(pos.totalPenjualanShift)}', style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('Total Seharusnya di Laci: ${currency.format(tercatatSistem)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const Divider(height: 20),
                  const Text('Hitung Uang Fisik di Laci Kasir:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: uangFisikCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Uang Fisik (Rp)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selisih == 0 ? AppTheme.lightGreenBg : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: selisih == 0 ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(selisih == 0 ? 'Status Kas: Sesuai' : 'Selisih Kas:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: selisih == 0 ? AppTheme.accentGreen : const Color(0xFFDC2626))),
                        Text(currency.format(selisih), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: selisih == 0 ? AppTheme.accentGreen : const Color(0xFFDC2626))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
              ElevatedButton(
                onPressed: () {
                  pos.tutupShiftKasir(fisik);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift kasir berhasil ditutup & dicatat ke sistem')));
                },
                child: const Text('Konfirmasi Tutup Shift'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTambahBarangDialog(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isManagerOrOwner = auth.canManagePrices;
    final userRoleLabel = auth.currentUser?.role.label ?? 'Kasir';

    final namaCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    final hargaBeliCtrl = TextEditingController();
    final hargaJualCtrl = TextEditingController();
    final marginPercentCtrl = TextEditingController(text: '40');
    final stokCtrl = TextEditingController(text: '10');
    final minStokCtrl = TextEditingController(text: '5');

    final pos = context.read<PosProvider>();
    final activeUnitId = pos.activeUnitId;
    final activeUnitNama = pos.activeUnitNama;

    // Generate random SKU default
    skuCtrl.text = 'PRD-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          void hitungHargaJualOtomatis() {
            final beli = double.tryParse(hargaBeliCtrl.text) ?? 0.0;
            final marginPct = double.tryParse(marginPercentCtrl.text) ?? 0.0;
            if (beli > 0) {
              final jual = beli + (beli * (marginPct / 100.0));
              hargaJualCtrl.text = jual.round().toString();
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isManagerOrOwner ? AppTheme.lightBlueBg : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isManagerOrOwner ? Icons.add_shopping_cart_rounded : Icons.lock_person_rounded,
                    color: isManagerOrOwner ? AppTheme.primaryBlue : const Color(0xFFD97706),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tambah Produk Kasir', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        isManagerOrOwner
                            ? 'Otoritas: $userRoleLabel (Berhak Atur HPP & Margin)'
                            : 'Login: $userRoleLabel (Harga Ditentukan oleh Manager)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isManagerOrOwner ? AppTheme.primaryBlue : const Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.storefront_rounded, size: 16, color: AppTheme.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Unit Usaha: $activeUnitNama (ID #$activeUnitId)',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: namaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nama Produk / Menu *',
                        hintText: 'Contoh: Es Kopi Susu Aren',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: skuCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Kode / SKU *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: stokCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Stok Awal *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // KOTAK PENGATURAN HARGA BERDASARKAN WEWENANG MANAGER VS KASIR
                    if (isManagerOrOwner) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.lightBlueBg.withAlpha(80),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.secondaryBlue.withAlpha(60)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Text('Kalkulator Harga & Margin (Manager)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                                Text('Rumus: Modal + Target Margin', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: hargaBeliCtrl,
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) => setDialogState(hitungHargaJualOtomatis),
                                    decoration: const InputDecoration(
                                      labelText: 'Harga Modal/HPP (Rp) *',
                                      hintText: '10000',
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: marginPercentCtrl,
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) => setDialogState(hitungHargaJualOtomatis),
                                    decoration: const InputDecoration(
                                      labelText: 'Margin %',
                                      hintText: '40',
                                      suffixText: '%',
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: hargaJualCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Harga Jual ke Pelanggan (Rp) *',
                                hintText: '14000',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.sell_rounded, color: AppTheme.accentGreen),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // JIKA LOGIN SEBAGAI KASIR BIASA:
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFD97706)),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Harga Modal dirahasiakan & telah ditentukan oleh Manager.',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: hargaJualCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Harga Jual Standar Menu (Rp) *',
                                hintText: '15000',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.sell_rounded, color: AppTheme.primaryBlue),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    TextField(
                      controller: minStokCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Batas Stok Kritis Minimum',
                        hintText: '5',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
              ElevatedButton(
                onPressed: () {
                  if (namaCtrl.text.trim().isEmpty || hargaJualCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nama barang dan harga jual wajib diisi!')),
                    );
                    return;
                  }

                  // Jika kasir menambah barang, harga modal diestimasi aman (65% harga jual) atau 0
                  final parsedJual = double.tryParse(hargaJualCtrl.text) ?? 0.0;
                  final double hargaBeli = isManagerOrOwner
                      ? (double.tryParse(hargaBeliCtrl.text) ?? (parsedJual * 0.65))
                      : (parsedJual * 0.65); // Estimasi HPP otomatis untuk kasir

                  final stok = int.tryParse(stokCtrl.text) ?? 10;
                  final minStok = int.tryParse(minStokCtrl.text) ?? 5;

                  final produkBaru = ProdukModel(
                    id: DateTime.now().millisecondsSinceEpoch,
                    unitId: activeUnitId,
                    nama: namaCtrl.text.trim(),
                    sku: skuCtrl.text.trim(),
                    hargaBeli: hargaBeli,
                    hargaJual: parsedJual,
                    stok: stok,
                    minStok: minStok,
                  );

                  context.read<ProdukProvider>().tambahProduk(produkBaru);
                  Navigator.pop(ctx);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.primaryBlue,
                      content: Text('Produk "${produkBaru.nama}" berhasil didaftarkan (Harga Jual: Rp ${parsedJual.round()})!'),
                    ),
                  );
                },
                child: const Text('Simpan Produk'),
              ),
            ],
          );
        },
      ),
    );
  }
}
