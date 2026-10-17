import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/gudang_model.dart';
import '../providers/gudang_provider.dart';
import '../providers/produk_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import 'dashboard_screen.dart';

class GudangScreen extends StatefulWidget {
  const GudangScreen({super.key});

  @override
  State<GudangScreen> createState() => _GudangScreenState();
}

class _GudangScreenState extends State<GudangScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen())),
        ),
        title: const Text('Gudang, Transfer & Stok Opname', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          TextButton.icon(
            onPressed: () => _showImportDialog(context),
            icon: const Icon(Icons.upload_file_rounded, size: 18, color: AppTheme.primaryBlue),
            label: const Text('Impor CSV/XLSX', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryBlue,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primaryBlue,
          tabs: const [
            Tab(icon: Icon(Icons.compare_arrows_rounded, size: 18), text: 'Transfer Antar-Unit'),
            Tab(icon: Icon(Icons.fact_check_rounded, size: 18), text: 'Stok Opname'),
            Tab(icon: Icon(Icons.swap_vert_rounded, size: 18), text: 'Mutasi Masuk/Keluar'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTransferTab(context, isMobile),
          _buildOpnameTab(context, isMobile),
          _buildMutasiTab(context, isMobile),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        onPressed: () {
          if (_tabController.index == 0) {
            _showKirimTransferDialog(context);
          } else if (_tabController.index == 1) {
            _showCatatOpnameDialog(context);
          } else {
            _showCatatMutasiDialog(context);
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tabController.index == 0
            ? 'Kirim Transfer Stok'
            : (_tabController.index == 1 ? 'Input Stok Opname' : 'Catat Mutasi Barang')),
      ),
    );
  }

  Widget _buildTransferTab(BuildContext context, bool isMobile) {
    final gudang = context.watch<GudangProvider>();
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
      itemCount: gudang.daftarTransfer.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final t = gudang.daftarTransfer[index];
        final isPending = t.status == StatusTransfer.pending;

        return Container(
          padding: const EdgeInsets.all(18),
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
                    children: [
                      const Icon(Icons.local_shipping_outlined, color: AppTheme.primaryBlue, size: 22),
                      const SizedBox(width: 10),
                      Text(t.namaProduk, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPending
                          ? const Color(0xFFFEF3C7)
                          : (t.status == StatusTransfer.diterima ? AppTheme.lightGreenBg : const Color(0xFFFEF2F2)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      t.status.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isPending
                            ? const Color(0xFFD97706)
                            : (t.status == StatusTransfer.diterima ? AppTheme.accentGreen : const Color(0xFFDC2626)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Dari Unit Asal:', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        Text(t.namaUnitAsal, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded, size: 18, color: AppTheme.textMuted),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Ke Unit Tujuan:', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        Text(t.namaUnitTujuan, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Jumlah: ${t.jumlah} unit • Dikirim: ${dateFormat.format(t.waktuKirim)}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  if (isPending)
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () => gudang.tolakTransfer(t.id),
                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                          child: const Text('Tolak'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => gudang.konfirmasiPenerimaan(t.id),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGreen),
                          child: const Text('Konfirmasi Diterima'),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOpnameTab(BuildContext context, bool isMobile) {
    final gudang = context.watch<GudangProvider>();
    final dateFormat = DateFormat('dd MMM yyyy');

    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
      itemCount: gudang.daftarOpname.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final o = gudang.daftarOpname[index];
        final isMatch = o.selisih == 0;

        return Container(
          padding: const EdgeInsets.all(18),
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
                  Text(o.namaProduk, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(dateFormat.format(o.tanggal), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
              const SizedBox(height: 4),
              Text(o.namaUnit, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Sistem: ${o.stokSistem} unit', style: const TextStyle(fontSize: 13)),
                  Text('Fisik: ${o.stokFisik} unit', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: isMatch ? AppTheme.lightGreenBg : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isMatch ? 'Selisih: Cocok' : 'Selisih: ${o.selisih} unit',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isMatch ? AppTheme.accentGreen : const Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
              ),
              if (o.alasan.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Catatan penyesuaian: "${o.alasan}"', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textMuted)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMutasiTab(BuildContext context, bool isMobile) {
    final gudang = context.watch<GudangProvider>();
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
      itemCount: gudang.daftarMutasi.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final m = gudang.daftarMutasi[index];
        final isMasuk = m.jenis == 'MASUK';

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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isMasuk ? AppTheme.lightGreenBg : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isMasuk ? Icons.call_received_rounded : Icons.call_made_rounded,
                  color: isMasuk ? AppTheme.accentGreen : const Color(0xFFDC2626),
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.namaProduk, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('Sumber/Tujuan: ${m.sumberTujuan}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isMasuk ? '+' : '-'}${m.jumlah} unit',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isMasuk ? AppTheme.accentGreen : const Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(dateFormat.format(m.tanggal), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Impor Master Produk & Stok', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.lightBlueBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.secondaryBlue.withAlpha(40), style: BorderStyle.solid),
                ),
                child: Column(
                  children: const [
                    Icon(Icons.file_upload_outlined, size: 40, color: AppTheme.primaryBlue),
                    SizedBox(height: 8),
                    Text('Pilih file CSV atau XLSX dari komputer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    SizedBox(height: 4),
                    Text('Format: SKU, Nama, Harga Beli, Harga Jual, Stok', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
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
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File berhasil diimpor! 45 data produk diperbarui.')));
            },
            child: const Text('Mulai Impor'),
          ),
        ],
      ),
    );
  }

  void _showKirimTransferDialog(BuildContext context) {
    final qtyCtrl = TextEditingController(text: '10');
    final produkList = Provider.of<ProdukProvider>(context, listen: false).daftarProduk;
    String selectedProduk = produkList.isNotEmpty ? produkList.first.nama : 'Biji Kopi Arabika';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Kirim Transfer Stok Antar-Unit', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedProduk,
                decoration: const InputDecoration(labelText: 'Pilih Produk', border: OutlineInputBorder()),
                items: produkList.map((p) => DropdownMenuItem(value: p.nama, child: Text(p.nama))).toList(),
                onChanged: (val) => setState(() => selectedProduk = val!),
              ),
              const SizedBox(height: 12),
              TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah Unit Dikirim', border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () {
                Provider.of<GudangProvider>(context, listen: false).kirimTransferStok(
                  TransferStokModel(
                    id: DateTime.now().millisecondsSinceEpoch,
                    unitAsalId: 1,
                    namaUnitAsal: 'Kedai Kopi Bahagia',
                    unitTujuanId: 2,
                    namaUnitTujuan: 'Laundry Bersih Kilat',
                    produkId: 1,
                    namaProduk: selectedProduk,
                    jumlah: int.tryParse(qtyCtrl.text) ?? 5,
                    waktuKirim: DateTime.now(),
                  ),
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permintaan transfer stok dikirim! Menunggu konfirmasi unit tujuan.')));
              },
              child: const Text('Kirim'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCatatOpnameDialog(BuildContext context) {
    final fisikCtrl = TextEditingController(text: '20');
    final alasanCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Catat Stok Opname Fisik', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: fisikCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah Stok Fisik Riil', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: alasanCtrl, decoration: const InputDecoration(labelText: 'Catatan Selisih (contoh: Rusak / Kadaluarsa)', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              Provider.of<GudangProvider>(context, listen: false).catatOpname(
                StokOpnameModel(
                  id: DateTime.now().millisecondsSinceEpoch,
                  unitId: 1,
                  namaUnit: 'Kedai Kopi Bahagia',
                  namaProduk: 'Biji Kopi Arabika 1kg',
                  stokSistem: 24,
                  stokFisik: int.tryParse(fisikCtrl.text) ?? 20,
                  alasan: alasanCtrl.text.isEmpty ? 'Penyesuaian stok berkala' : alasanCtrl.text,
                  tanggal: DateTime.now(),
                ),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Simpan Opname'),
          ),
        ],
      ),
    );
  }

  void _showCatatMutasiDialog(BuildContext context) {
    final qtyCtrl = TextEditingController(text: '10');
    final sumberCtrl = TextEditingController();
    String jenis = 'MASUK';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Catat Barang Masuk / Keluar', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: jenis,
                decoration: const InputDecoration(labelText: 'Jenis Mutasi', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'MASUK', child: Text('Barang Masuk (Pemasok)')),
                  DropdownMenuItem(value: 'KELUAR', child: Text('Barang Keluar (Operasional)')),
                ],
                onChanged: (val) => setState(() => jenis = val!),
              ),
              const SizedBox(height: 12),
              TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah Unit', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: sumberCtrl, decoration: const InputDecoration(labelText: 'Sumber / Pemasok / Pengguna', border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () {
                Provider.of<GudangProvider>(context, listen: false).catatMutasi(
                  MutasiStokModel(
                    id: DateTime.now().millisecondsSinceEpoch,
                    jenis: jenis,
                    namaProduk: 'Biji Kopi Arabika 1kg',
                    jumlah: int.tryParse(qtyCtrl.text) ?? 10,
                    sumberTujuan: sumberCtrl.text.isEmpty ? 'Pemasok Umum' : sumberCtrl.text,
                    tanggal: DateTime.now(),
                  ),
                );
                Navigator.pop(ctx);
              },
              child: const Text('Simpan Mutasi'),
            ),
          ],
        ),
      ),
    );
  }
}
