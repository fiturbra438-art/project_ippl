import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/notifikasi_model.dart';
import '../providers/notifikasi_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import 'dashboard_screen.dart';

class NotifikasiScreen extends StatelessWidget {
  const NotifikasiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final provider = context.watch<NotifikasiProvider>();
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

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
            const Text('Pusat Notifikasi & Peringatan', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
            if (provider.unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(10)),
                child: Text('${provider.unreadCount} baru', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => provider.tandaiSemuaDibaca(),
            child: const Text('Tandai Semua Dibaca', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
        itemCount: provider.daftarNotifikasi.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final n = provider.daftarNotifikasi[index];

          return InkWell(
            onTap: () => provider.tandaiDibaca(n.id),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: n.isDibaca ? AppTheme.surfaceWhite : const Color(0xFFF0F5FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: n.isDibaca ? AppTheme.cardBorder : AppTheme.secondaryBlue.withAlpha(50)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: _getBgColor(n.jenis),
                    child: Icon(_getIcon(n.jenis), color: _getIconColor(n.jenis), size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(n.judul, style: TextStyle(fontWeight: n.isDibaca ? FontWeight.w600 : FontWeight.bold, fontSize: 14)),
                            Text(dateFormat.format(n.waktu), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(n.pesan, style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textPrimary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _getIcon(JenisNotifikasi jenis) {
    switch (jenis) {
      case JenisNotifikasi.stokMenipis:
        return Icons.inventory_2_outlined;
      case JenisNotifikasi.anomali:
        return Icons.warning_amber_rounded;
      case JenisNotifikasi.rekomendasiAi:
        return Icons.auto_awesome_rounded;
      case JenisNotifikasi.transferStok:
        return Icons.local_shipping_outlined;
    }
  }

  Color _getIconColor(JenisNotifikasi jenis) {
    switch (jenis) {
      case JenisNotifikasi.stokMenipis:
        return const Color(0xFFD97706);
      case JenisNotifikasi.anomali:
        return const Color(0xFFDC2626);
      case JenisNotifikasi.rekomendasiAi:
        return AppTheme.primaryBlue;
      case JenisNotifikasi.transferStok:
        return AppTheme.accentGreen;
    }
  }

  Color _getBgColor(JenisNotifikasi jenis) {
    switch (jenis) {
      case JenisNotifikasi.stokMenipis:
        return const Color(0xFFFEF3C7);
      case JenisNotifikasi.anomali:
        return const Color(0xFFFEF2F2);
      case JenisNotifikasi.rekomendasiAi:
        return AppTheme.lightBlueBg;
      case JenisNotifikasi.transferStok:
        return AppTheme.lightGreenBg;
    }
  }
}
