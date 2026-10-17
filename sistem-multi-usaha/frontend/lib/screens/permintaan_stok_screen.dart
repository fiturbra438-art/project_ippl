import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/permintaan_stok_model.dart';
import '../providers/permintaan_stok_provider.dart';
import '../providers/produk_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import 'dashboard_screen.dart';

class PermintaanStokScreen extends StatelessWidget {
  const PermintaanStokScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final provider = context.watch<PermintaanStokProvider>();
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen())),
        ),
        title: const Text('Permintaan Tambahan Stok (Manager)', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
        itemCount: provider.daftarPermintaan.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final p = provider.daftarPermintaan[index];
          final isPending = p.status == StatusPermintaanStok.pending;

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
                        const Icon(Icons.inventory_rounded, color: AppTheme.primaryBlue, size: 20),
                        const SizedBox(width: 8),
                        Text(p.namaProduk, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    _buildStatusBadge(p.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Pemohon: ${p.pemohon} • Unit: ${p.namaUnit}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 10),
                Text('Alasan: "${p.alasan}"', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Permintaan: ${p.jumlahDiminta} unit • Diajukan: ${dateFormat.format(p.waktuPengajuan)}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    if (isPending)
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: () => provider.tolakPermintaan(p.id),
                            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                            child: const Text('Tolak'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => provider.setujuiPermintaan(p.id),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGreen),
                            child: const Text('Setujui Restok'),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        onPressed: () => _showAjukanPermintaanDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Ajukan Permintaan Stok'),
      ),
    );
  }

  Widget _buildStatusBadge(StatusPermintaanStok status) {
    Color bg = const Color(0xFFFEF3C7);
    Color text = const Color(0xFFD97706);

    if (status == StatusPermintaanStok.disetujui) {
      bg = AppTheme.lightGreenBg;
      text = AppTheme.accentGreen;
    } else if (status == StatusPermintaanStok.ditolak) {
      bg = const Color(0xFFFEF2F2);
      text = const Color(0xFFDC2626);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: text),
      ),
    );
  }

  void _showAjukanPermintaanDialog(BuildContext context) {
    final qtyCtrl = TextEditingController(text: '25');
    final alasanCtrl = TextEditingController();
    final produkList = Provider.of<ProdukProvider>(context, listen: false).daftarProduk;
    String selectedProduk = produkList.isNotEmpty ? produkList.first.nama : 'Biji Kopi Arabika 1kg';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Form Pengajuan Tambahan Stok', style: TextStyle(fontWeight: FontWeight.bold)),
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
              TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah Tambahan yang Diminta', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: alasanCtrl, decoration: const InputDecoration(labelText: 'Alasan Permintaan (lonjakan pembeli, dll)', border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () {
                Provider.of<PermintaanStokProvider>(context, listen: false).ajukanPermintaan(
                  PermintaanStokModel(
                    id: DateTime.now().millisecondsSinceEpoch,
                    unitId: 1,
                    namaUnit: 'Kedai Kopi Bahagia',
                    pemohon: 'Manager Unit',
                    namaProduk: selectedProduk,
                    jumlahDiminta: int.tryParse(qtyCtrl.text) ?? 20,
                    alasan: alasanCtrl.text.isEmpty ? 'Kebutuhan operasional mendesak' : alasanCtrl.text,
                    waktuPengajuan: DateTime.now(),
                  ),
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permintaan terkirim ke Owner & Admin Gudang!')));
              },
              child: const Text('Kirim Pengajuan'),
            ),
          ],
        ),
      ),
    );
  }
}
