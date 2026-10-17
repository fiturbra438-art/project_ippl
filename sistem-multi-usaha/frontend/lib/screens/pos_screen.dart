import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/produk.dart';
import '../providers/pos_provider.dart';
import '../providers/produk_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
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
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen())),
        ),
        title: Row(
          children: [
            const Text('Mesin Kasir (POS)', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
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
      ],
    );
  }

  Widget _buildProductCatalog() {
    final produkList = context.watch<ProdukProvider>().daftarProduk;

    if (produkList.isEmpty) {
      return const Center(child: Text('Produk tidak ditemukan'));
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
}
