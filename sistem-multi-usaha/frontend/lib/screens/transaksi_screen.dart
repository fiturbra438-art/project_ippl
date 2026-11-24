import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/transaksi.dart';
import '../models/user_model.dart';
import '../providers/transaksi_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/usaha_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_sidebar.dart';
import 'dashboard_screen.dart';
import 'usaha_screen.dart';

class TransaksiScreen extends StatefulWidget {
  const TransaksiScreen({super.key});

  @override
  State<TransaksiScreen> createState() => _TransaksiScreenState();
}

class _TransaksiScreenState extends State<TransaksiScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TransaksiProvider>().fetchTransaksiFromApi();
    });
  }

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
          if (!isMobile) const AppSidebar(activeRoute: 'transaksi'),
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
              const Icon(Icons.receipt_long_outlined, size: 56, color: AppTheme.primaryBlue),
              const SizedBox(height: 16),
              const Text('Belum Ada Riwayat Transaksi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              const SizedBox(height: 6),
              const Text(
                'Arus kas masuk atau keluar dari penjualan POS dan pencatatan manual akan tampil di sini secara real-time.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => _showTambahTransaksiDialog(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Catat Transaksi Manual'),
              ),
            ],
          ),
        ),
      );
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isIncome ? '+' : '-'}${currency.format(item.jumlah)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isIncome ? AppTheme.accentGreen : const Color(0xFFEF4444),
                    ),
                  ),
                  if (item.kategori == 'Penjualan POS' && _canRefund(context))
                    TextButton(
                      onPressed: () => _showRefundDialog(context, item),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 28),
                      ),
                      child: const Text('Refund', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  bool _canRefund(BuildContext context) {
    final role = context.watch<AuthProvider>().currentUser?.role;
    return role == UserRole.owner || role == UserRole.manager;
  }

  Future<void> _showRefundDialog(BuildContext context, TransaksiModel transaksi) async {
    final provider = context.read<TransaksiProvider>();
    final detail = await provider.fetchTransaksiDetail(transaksi.id);
    if (!context.mounted) return;
    if (detail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.lastError ?? 'Gagal memuat detail transaksi.')),
      );
      return;
    }

    final alasanCtrl = TextEditingController();
    final qtyCtrls = <int, TextEditingController>{
      for (final item in detail.items)
        if (item.refundableQty > 0) item.id: TextEditingController(text: '0'),
    };
    var voidMode = false;
    var submitting = false;
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Refund Transaksi #${transaksi.id}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total transaksi ${currency.format(detail.total)} • Sudah direfund ${currency.format(detail.refundedTotal)} • Sisa ${currency.format(detail.refundableTotal)}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Void / refund penuh sisa transaksi'),
                    subtitle: const Text('Semua item yang belum direfund akan diproses.'),
                    value: voidMode,
                    onChanged: submitting
                        ? null
                        : (value) => setLocalState(() => voidMode = value),
                  ),
                  if (!voidMode) ...[
                    const SizedBox(height: 8),
                    const Text('Pilih jumlah item yang direfund:', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    ...detail.items.map((item) {
                      if (item.refundableQty <= 0) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.itemName),
                          subtitle: Text('Sudah direfund penuh (${item.refundedQty}/${item.qty})'),
                        );
                      }
                      return Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.itemName} (${item.itemType}) • sisa ${item.refundableQty}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: qtyCtrls[item.id],
                              keyboardType: TextInputType.number,
                              enabled: !submitting,
                              decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: alasanCtrl,
                    enabled: !submitting,
                    decoration: const InputDecoration(
                      labelText: 'Alasan refund (wajib)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final alasan = alasanCtrl.text.trim();
                      if (alasan.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Alasan refund wajib diisi.')),
                        );
                        return;
                      }
                      final items = <int, int>{};
                      if (!voidMode) {
                        for (final entry in qtyCtrls.entries) {
                          final qty = int.tryParse(entry.value.text.trim()) ?? 0;
                          if (qty > 0) items[entry.key] = qty;
                        }
                        if (items.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Pilih minimal satu item dengan qty > 0.')),
                          );
                          return;
                        }
                      }
                      setLocalState(() => submitting = true);
                      final ok = await provider.ajukanRefund(
                        id: transaksi.id,
                        alasan: alasan,
                        voidMode: voidMode,
                        items: items,
                      );
                      if (!ctx.mounted) return;
                      setLocalState(() => submitting = false);
                      if (ok) Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Refund berhasil diproses.'
                                : (provider.lastError ?? 'Gagal memproses refund.'),
                          ),
                        ),
                      );
                    },
              child: Text(submitting ? 'Memproses...' : 'Proses Refund'),
            ),
          ],
        ),
      ),
    );
    for (final controller in qtyCtrls.values) {
      controller.dispose();
    }
    alasanCtrl.dispose();
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
              onPressed: () async {
                final nominal = double.tryParse(jumlahCtrl.text) ?? 0;
                final selectedUnitId = context.read<AuthProvider>().selectedUnitId;
                final units = context.read<UsahaProvider>().daftarUsaha;
                final unitId = selectedUnitId ??
                    (units.isEmpty ? null : units.first.id);
                final kategori = kategoriCtrl.text.trim();
                if (nominal <= 0 || kategori.isEmpty || unitId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Pilih unit dan isi kategori serta nominal yang valid.'),
                    ),
                  );
                  return;
                }
                final provider = context.read<TransaksiProvider>();
                final success = await provider.catatTransaksiManual(
                  unitId: unitId,
                  jenis: jenis,
                  kategori: kategori,
                  jumlah: nominal,
                );
                if (!ctx.mounted) return;
                if (success) Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Transaksi berhasil disimpan.'
                          : (provider.lastError ?? 'Gagal menyimpan transaksi.'),
                    ),
                  ),
                );
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
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
