import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/gudang_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/gudang_provider.dart';
import '../providers/produk_provider.dart';
import '../providers/usaha_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_navigator.dart';
import 'dashboard_screen.dart';
import 'manager_dashboard_screen.dart';
import 'login_screen.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final unitId = auth.selectedUnitId;
      context.read<GudangProvider>().fetchTransferFromApi(unitId: unitId);
      context.read<GudangProvider>().fetchOpnameFromApi(unitId: unitId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final auth = context.watch<AuthProvider>();
    final isAdminGudang = auth.currentUser?.role == UserRole.adminGudang;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceWhite,
        elevation: 0,
        leading: isAdminGudang
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                onPressed: () {
                  if (auth.currentUser?.role == UserRole.manager) {
                    AppNavigator.backToDashboard(context, const ManagerDashboardScreen());
                  } else {
                    AppNavigator.backToDashboard(context, const DashboardScreen());
                  }
                },
              ),
        title: Text(isAdminGudang ? 'Portal Gudang & Logistik' : 'Gudang, Transfer & Stok Opname', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          TextButton.icon(
            onPressed: () => _showImportDialog(context),
            icon: const Icon(Icons.upload_file_rounded, size: 18, color: AppTheme.primaryBlue),
            label: const Text('Impor CSV (segera)', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
          ),
          if (isAdminGudang)
            IconButton(
              tooltip: 'Keluar / Logout Gudang',
              icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
              onPressed: () {
                auth.logout();
                AppNavigator.pushReplacementFullscreen(context, const LoginScreen());
              },
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
        onPressed: _tabController.index == 2 ? null : () {
          if (_tabController.index == 0) {
            _showKirimTransferDialog(context);
          } else if (_tabController.index == 1) {
            _showCatatOpnameDialog(context);
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tabController.index == 0
            ? 'Kirim Transfer Stok'
            : (_tabController.index == 1 ? 'Input Stok Opname' : 'Mutasi (preview saja)')),
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
                          : (t.status == StatusTransfer.diterima || t.status == StatusTransfer.disetujui || t.status == StatusTransfer.dikirim
                              ? AppTheme.lightGreenBg
                              : const Color(0xFFFEF2F2)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      t.status.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isPending
                            ? const Color(0xFFD97706)
                            : (t.status == StatusTransfer.diterima || t.status == StatusTransfer.disetujui || t.status == StatusTransfer.dikirim
                                ? AppTheme.accentGreen
                                : const Color(0xFFDC2626)),
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
                          onPressed: () => _showRejectionDialog(context, t.id),
                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                          child: const Text('Tolak'),
                        ),
                        TextButton(
                          onPressed: () => _runTransferAction(
                            context,
                            () => gudang.batalkanTransfer(t.id),
                            'Permintaan transfer dibatalkan.',
                          ),
                          child: const Text('Batalkan'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _runTransferAction(
                            context,
                            () => gudang.setujuiTransfer(t.id),
                            'Permintaan transfer disetujui.',
                          ),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGreen),
                          child: const Text('Setujui'),
                        ),
                      ],
                    ),
                  if (t.status == StatusTransfer.disetujui)
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => _runTransferAction(
                            context,
                            () => gudang.batalkanTransfer(t.id),
                            'Transfer dibatalkan dan reservasi dilepas.',
                          ),
                          child: const Text('Batalkan'),
                        ),
                        ElevatedButton(
                          onPressed: () => _runTransferAction(
                            context,
                            () => gudang.kirimTransfer(t.id),
                            'Stok asal telah dikurangi dan transfer dikirim.',
                          ),
                          child: const Text('Kirim'),
                        ),
                      ],
                    ),
                  if (t.status == StatusTransfer.dikirim)
                    ElevatedButton(
                      onPressed: () => _runTransferAction(
                        context,
                        () => gudang.konfirmasiPenerimaan(t.id),
                        'Penerimaan transfer berhasil dicatat.',
                      ),
                      child: const Text('Konfirmasi Diterima'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _runTransferAction(
    BuildContext context,
    Future<bool> Function() action,
    String successMessage,
  ) async {
    final success = await action();
    if (!context.mounted) return;
    final error = context.read<GudangProvider>().lastError;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? successMessage : (error ?? 'Aksi transfer gagal.'))),
    );
  }

  Future<void> _showRejectionDialog(BuildContext context, int id) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tolak transfer stok'),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Alasan penolakan'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Tolak'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || !context.mounted) return;
    await _runTransferAction(
      context,
      () => context.read<GudangProvider>().tolakTransfer(id, alasan: reason),
      'Permintaan transfer ditolak.',
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

    if (gudang.daftarMutasi.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Mutasi manual belum tersedia. Data stok hanya berubah melalui transaksi backend yang tercatat.'),
        ),
      );
    }

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
        title: const Text('Impor produk belum tersedia', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    Text('Import dinonaktifkan sampai pemilih file, validasi, dan penyimpanan batch tersedia.', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13), textAlign: TextAlign.center),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          const ElevatedButton(onPressed: null, child: Text('Impor dinonaktifkan')),
        ],
      ),
    );
  }

  void _showKirimTransferDialog(BuildContext context) {
    final qtyCtrl = TextEditingController();
    final unitId = context.read<AuthProvider>().selectedUnitId;
    if (unitId == null) return;
    final produkList = context.read<ProdukProvider>().daftarProduk
        .where((product) => product.unitId == unitId)
        .toList();
    final unitList = context.read<UsahaProvider>().daftarUsaha;
    final tujuanList = unitList.where((u) => u.id != unitId).toList();
    if (produkList.isEmpty || tujuanList.isEmpty) return;
    int selectedProduk = produkList.first.id;
    int selectedTujuan = tujuanList.first.id;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Kirim Transfer Stok Antar-Unit', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: selectedProduk,
                decoration: const InputDecoration(labelText: 'Pilih Produk', border: OutlineInputBorder()),
                items: produkList.map((p) => DropdownMenuItem(value: p.id, child: Text(p.nama))).toList(),
                onChanged: (val) => setState(() => selectedProduk = val!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: selectedTujuan,
                decoration: const InputDecoration(labelText: 'Unit Tujuan', border: OutlineInputBorder()),
                items: tujuanList.map((u) => DropdownMenuItem(value: u.id, child: Text(u.nama))).toList(),
                onChanged: (val) => setState(() => selectedTujuan = val!),
              ),
              const SizedBox(height: 12),
              TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah Unit Dikirim', border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final ok = await context.read<GudangProvider>().kirimTransferStok(TransferStokModel(
                  id: 0, unitAsalId: unitId, namaUnitAsal: '', unitTujuanId: selectedTujuan, namaUnitTujuan: '',
                  produkId: selectedProduk, namaProduk: '', jumlah: int.tryParse(qtyCtrl.text) ?? 0, waktuKirim: DateTime.now(),
                ));
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Permintaan transfer stok berhasil diajukan.' : (context.read<GudangProvider>().lastError ?? 'Transfer stok gagal.'))));
              },
              child: const Text('Kirim'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCatatOpnameDialog(BuildContext context) {
    final fisikCtrl = TextEditingController();
    final alasanCtrl = TextEditingController();
    final unitId = context.read<AuthProvider>().selectedUnitId;
    final products = context.read<ProdukProvider>().daftarProduk.where((p) => p.unitId == unitId).toList();
    if (unitId == null || products.isEmpty) return;
    int selectedProduct = products.first.id;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Catat Stok Opname Fisik', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            value: selectedProduct,
            decoration: const InputDecoration(labelText: 'Pilih Produk', border: OutlineInputBorder()),
            items: products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.nama))).toList(),
            onChanged: (value) => setState(() => selectedProduct = value!),
          ),
          const SizedBox(height: 12),
          TextField(controller: fisikCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah Stok Fisik Riil', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: alasanCtrl, decoration: const InputDecoration(labelText: 'Catatan Selisih', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(onPressed: () async {
            final product = products.firstWhere((p) => p.id == selectedProduct);
            final ok = await context.read<GudangProvider>().catatOpname(StokOpnameModel(
              id: 0, unitId: unitId, namaUnit: '', productId: product.id, namaProduk: product.nama,
              stokSistem: product.stok, stokFisik: int.tryParse(fisikCtrl.text) ?? -1,
              alasan: alasanCtrl.text, tanggal: DateTime.now(),
            ));
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Stok opname berhasil disimpan.' : (context.read<GudangProvider>().lastError ?? 'Stok opname gagal.'))));
          }, child: const Text('Simpan Opname')),
        ],
      )),
    );
  }

}
