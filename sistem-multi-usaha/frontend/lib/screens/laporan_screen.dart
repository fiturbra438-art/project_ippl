import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/laporan_provider.dart';
import '../providers/usaha_provider.dart';
import '../services/laporan_csv.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_sidebar.dart';
import 'dashboard_screen.dart';
import 'usaha_screen.dart';
import 'transaksi_screen.dart';
import 'chat_ai_screen.dart';

class LaporanScreen extends StatefulWidget {
  const LaporanScreen({super.key});

  @override
  State<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends State<LaporanScreen> {
  DateTime? _tanggalMulai;
  DateTime? _tanggalAkhir;
  int? _unitId;
  String? _metodePembayaran;
  String? _statusTransaksi = 'selesai';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LaporanProvider>().fetchLaporanFromApi();
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
              title: const Text('Laporan Finansial', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
              actions: [
                IconButton(
                  tooltip: 'Ekspor CSV',
                  icon: const Icon(Icons.download_rounded, color: AppTheme.primaryBlue),
                  onPressed: () => _exportCsv(context),
                ),
              ],
            )
          : null,
      drawer: isMobile ? _buildNavigationDrawer(context) : null,
      body: Row(
        children: [
          if (!isMobile) const AppSidebar(activeRoute: 'laporan'),
          Expanded(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMobile) _buildDesktopHeader(context),
                    const SizedBox(height: 24),
                    _buildFilters(context),
                    const SizedBox(height: 20),
                    if (context.watch<LaporanProvider>().isLoading)
                      const LinearProgressIndicator(),
                    if (context.watch<LaporanProvider>().lastError != null)
                      _buildError(context),
                    if (!context.watch<LaporanProvider>().isLoading &&
                        context.watch<LaporanProvider>().lastError == null &&
                        context.watch<LaporanProvider>().summary.totalPemasukan == 0 &&
                        context.watch<LaporanProvider>().summary.totalPengeluaran == 0)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text('Tidak ada data pada filter periode ini.'),
                      ),
                    _buildSummaryFinancialCards(context),
                    const SizedBox(height: 28),
                    _buildBreakdownSection(context, isMobile),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
            Text('Laporan Keuangan & Laba Rugi', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            SizedBox(height: 4),
            Text('Konsolidasi pemasukan, beban operasional, dan kontribusi laba lintas unit.', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          ],
        ),
        ElevatedButton.icon(
          onPressed: () => _exportCsv(context),
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('Ekspor CSV'),
        ),
      ],
    );
  }

  Widget _buildFilters(BuildContext context) {
    final units = context.watch<UsahaProvider>().daftarUsaha;
    final provider = context.watch<LaporanProvider>();
    final dateFormat = DateFormat('dd MMM yyyy');
    final paymentOptions = <String?>[null, 'Tunai', 'QRIS', 'Transfer Bank'];
    final statusOptions = <String?>['selesai', 'dibatalkan'];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<int?>(
            value: _unitId,
            decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Semua unit yang dapat diakses')),
              ...units.map((unit) => DropdownMenuItem<int?>(
                    value: unit.id,
                    child: Text(unit.nama, overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (value) => setState(() => _unitId = value),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickDate(context, start: true),
          icon: const Icon(Icons.calendar_today, size: 16),
          label: Text(_tanggalMulai == null ? 'Tanggal mulai' : dateFormat.format(_tanggalMulai!)),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickDate(context, start: false),
          icon: const Icon(Icons.event, size: 16),
          label: Text(_tanggalAkhir == null ? 'Tanggal akhir' : dateFormat.format(_tanggalAkhir!)),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String?>(
            value: _metodePembayaran,
            decoration: const InputDecoration(labelText: 'Pembayaran', border: OutlineInputBorder()),
            items: paymentOptions
                .map((value) => DropdownMenuItem<String?>(
                      value: value,
                      child: Text(value ?? 'Semua metode'),
                    ))
                .toList(),
            onChanged: (value) => setState(() => _metodePembayaran = value),
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String?>(
            value: _statusTransaksi,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
            items: statusOptions
                .map((value) => DropdownMenuItem<String?>(
                      value: value,
                      child: Text(value == 'selesai' ? 'Selesai' : 'Dibatalkan'),
                    ))
                .toList(),
            onChanged: (value) => setState(() => _statusTransaksi = value),
          ),
        ),
        ElevatedButton(
          onPressed: provider.isLoading ? null : () => _loadFiltered(context),
          child: const Text('Terapkan filter'),
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context, {required bool start}) async {
    final value = await showDatePicker(
      context: context,
      initialDate: (start ? _tanggalMulai : _tanggalAkhir) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) {
      setState(() {
        if (start) {
          _tanggalMulai = value;
        } else {
          _tanggalAkhir = value;
        }
      });
    }
  }

  Future<void> _loadFiltered(BuildContext context) async {
    await context.read<LaporanProvider>().fetchLaporanFromApi(
          unitId: _unitId,
          tanggalMulai: _tanggalMulai,
          tanggalAkhir: _tanggalAkhir,
          metodePembayaran: _metodePembayaran,
          statusTransaksi: _statusTransaksi,
        );
  }

  void _exportCsv(BuildContext context) {
    final provider = context.read<LaporanProvider>();
    final units = context.read<UsahaProvider>().daftarUsaha;
    var unitName = _unitId == null ? 'Semua unit' : 'Unit $_unitId';
    if (_unitId != null) {
      for (final unit in units) {
        if (unit.id == _unitId) {
          unitName = unit.nama;
          break;
        }
      }
    }
    final periode = _tanggalMulai == null && _tanggalAkhir == null
        ? 'Semua periode'
        : '${_tanggalMulai == null ? '-' : DateFormat('yyyy-MM-dd').format(_tanggalMulai!)} s/d ${_tanggalAkhir == null ? '-' : DateFormat('yyyy-MM-dd').format(_tanggalAkhir!)}';
    final stamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
    try {
      exportLaporanCsv(
        'laporan-keuangan-$stamp.csv',
        buildLaporanCsv(provider.summary, periode: periode, unit: unitName),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ekspor CSV berhasil.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ekspor gagal: $error')),
      );
    }
  }

  Widget _buildError(BuildContext context) {
    final provider = context.watch<LaporanProvider>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(child: Text(provider.lastError!, style: const TextStyle(color: Colors.red))),
          TextButton(
            onPressed: provider.isLoading ? null : () => _loadFiltered(context),
            child: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryFinancialCards(BuildContext context) {
    final provider = context.watch<LaporanProvider>();
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 750;
        final cardWidth = isNarrow ? constraints.maxWidth : (constraints.maxWidth - 32) / 3;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard(
              title: 'Total Pemasukan Konsolidasi',
              value: currency.format(provider.summary.totalPemasukan),
              subtext: 'Kotor ${currency.format(provider.summary.omzetKotor)} • Diskon ${currency.format(provider.summary.diskon)}',
              color: AppTheme.primaryBlue,
              bg: AppTheme.lightBlueBg,
              icon: Icons.account_balance_wallet_rounded,
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Total Beban & Pengeluaran',
              value: currency.format(provider.summary.totalPengeluaran),
              subtext: 'HPP ${currency.format(provider.summary.hpp)} • Refund ${currency.format(provider.summary.refund)}',
              color: const Color(0xFFDC2626),
              bg: const Color(0xFFFEF2F2),
              icon: Icons.money_off_rounded,
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Laba Bersih Operasional',
              value: currency.format(provider.summary.labaOperasional),
              subtext: 'Margin Laba: ${provider.summary.marginLabaPersen}%',
              color: AppTheme.accentGreen,
              bg: AppTheme.lightGreenBg,
              icon: Icons.check_circle_outline_rounded,
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtext,
    required Color color,
    required Color bg,
    required IconData icon,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
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
              Text(title, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              CircleAvatar(radius: 18, backgroundColor: bg, child: Icon(icon, color: color, size: 18)),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 6),
          Text(subtext, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _buildBreakdownSection(BuildContext context, bool isMobile) {
    final provider = context.watch<LaporanProvider>();
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Kontribusi Laba Bersih per Unit Usaha', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppTheme.surfaceWhite, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.cardBorder)),
          child: Column(
            children: provider.summary.performaUnit.map((unit) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(unit.namaUnit, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('${currency.format(unit.labaBersih)} (${unit.kontribusiPersen}%)', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentGreen, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: unit.kontribusiPersen / 100,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Komposisi Beban Operasional', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppTheme.surfaceWhite, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.cardBorder)),
          child: Column(
            children: provider.summary.rincianPengeluaran.map((kategori) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.circle, size: 10, color: AppTheme.secondaryBlue),
                        const SizedBox(width: 10),
                        Text(kategori.nama, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    Text(
                      '${currency.format(kategori.nominal)} (${kategori.persen}%)',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
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
            leading: const Icon(Icons.assessment_rounded, color: AppTheme.primaryBlue),
            title: const Text('Laporan Keuangan'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_rounded),
            title: const Text('Asisten AI'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ChatAiScreen()));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomBar(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 3,
      onTap: (index) {
        if (index == 0) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
        } else if (index == 1) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UsahaScreen()));
        } else if (index == 2) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TransaksiScreen()));
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
        BottomNavigationBarItem(icon: Icon(Icons.assessment_rounded), label: 'Laporan'),
      ],
    );
  }
}
