import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/ai_models.dart';
import '../providers/ai_suite_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import 'dashboard_screen.dart';

class AiHubScreen extends StatefulWidget {
  const AiHubScreen({super.key});

  @override
  State<AiHubScreen> createState() => _AiHubScreenState();
}

class _AiHubScreenState extends State<AiHubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
        title: Row(
          children: const [
            Icon(Icons.auto_awesome_rounded, color: AppTheme.primaryBlue, size: 22),
            SizedBox(width: 8),
            Text('Owner AI Intelligence Suite', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: isMobile,
          labelColor: AppTheme.primaryBlue,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primaryBlue,
          tabs: const [
            Tab(icon: Icon(Icons.show_chart_rounded, size: 18), text: 'Prediksi Permintaan'),
            Tab(icon: Icon(Icons.move_up_rounded, size: 18), text: 'Realokasi Stok AI'),
            Tab(icon: Icon(Icons.security_update_warning_rounded, size: 18), text: 'Deteksi Anomali'),
            Tab(icon: Icon(Icons.calculate_outlined, size: 18), text: 'Simulasi What-If Modal'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPrediksiPermintaanTab(context, isMobile),
          _buildRealokasiStokTab(context, isMobile),
          _buildDeteksiAnomaliTab(context, isMobile),
          _buildWhatIfSimulasiTab(context, isMobile),
        ],
      ),
    );
  }

  // TAB 1: Prediksi Permintaan 7 & 30 Hari
  Widget _buildPrediksiPermintaanTab(BuildContext context, bool isMobile) {
    final ai = context.watch<AiSuiteProvider>();

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Ramalan Penjualan & Permintaan Stok', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 2),
                  Text('Estimasi machine learning untuk mencegah stockout & overstock', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('7 Hari'),
                    selected: ai.horizonHari == 7,
                    selectedColor: AppTheme.lightBlueBg,
                    labelStyle: TextStyle(fontWeight: FontWeight.bold, color: ai.horizonHari == 7 ? AppTheme.primaryBlue : AppTheme.textSecondary),
                    onSelected: (_) => ai.setHorizonHari(7),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('30 Hari'),
                    selected: ai.horizonHari == 30,
                    selectedColor: AppTheme.lightBlueBg,
                    labelStyle: TextStyle(fontWeight: FontWeight.bold, color: ai.horizonHari == 30 ? AppTheme.primaryBlue : AppTheme.textSecondary),
                    onSelected: (_) => ai.setHorizonHari(30),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Legend status
          Row(
            children: [
              _buildLegend(const Color(0xFFDC2626), 'Risiko Kehabisan (Stockout)'),
              const SizedBox(width: 14),
              _buildLegend(const Color(0xFFD97706), 'Risiko Kelebihan (Overstock)'),
              const SizedBox(width: 14),
              _buildLegend(AppTheme.accentGreen, 'Aman / Optimal'),
            ],
          ),
          const SizedBox(height: 18),
          // Visualisasi Bar Prediksi vs Aktual
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              children: ai.listPrediksi.map((p) {
                final isRiskOut = p.statusRisiko == 'RISIKO_KEHABISAN';
                final isRiskOver = p.statusRisiko == 'RISIKO_KELEBIHAN';
                Color barColor = isRiskOut ? const Color(0xFFDC2626) : (isRiskOver ? const Color(0xFFD97706) : AppTheme.primaryBlue);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(width: 60, child: Text(p.periode, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (p.prediksi / 70).clamp(0.05, 1.0),
                            minHeight: 14,
                            backgroundColor: const Color(0xFFF1F5F9),
                            valueColor: AlwaysStoppedAnimation<Color>(barColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 90,
                        child: Text(
                          '${p.prediksi.toInt()} unit',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: barColor),
                        ),
                      ),
                      if (isRiskOut)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(4)),
                          child: const Text('Warning Stockout', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                        ),
                      if (isRiskOver)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)),
                          child: const Text('Overstock', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }

  // TAB 2: Realokasi Stok AI
  Widget _buildRealokasiStokTab(BuildContext context, bool isMobile) {
    final ai = context.watch<AiSuiteProvider>();

    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
      itemCount: ai.daftarRealokasi.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final r = ai.daftarRealokasi[index];
        final isPending = r.status == StatusRekomendasi.pending;

        return Container(
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
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: AppTheme.secondaryBlue, size: 20),
                      const SizedBox(width: 8),
                      Text('Rekomendasi Pindahkan ${r.jumlahPindah} Unit: ${r.namaProduk}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  _buildStatusChip(r.status),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppTheme.lightBlueBg, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Unit Sumber (Kelebihan):', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          Text(r.unitSumber, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, color: AppTheme.primaryBlue, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Unit Tujuan (Kekurangan):', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          Text(r.unitTujuan, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Alasan AI: "${r.alasanAi}"', style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              Text('Estimasi Efisiensi Biaya Pembelian Baru: ${currency.format(r.estimasiHematBiaya)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentGreen)),
              const Divider(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Sifat: Penasihat (Stok hanya berpindah setelah Anda setujui)', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textMuted)),
                  if (isPending)
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () => ai.tolakRealokasiStok(r.id),
                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                          child: const Text('Tolak'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => ai.setujuiRealokasiStok(r.id),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGreen),
                          child: const Text('Setujui Realokasi'),
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

  Widget _buildStatusChip(StatusRekomendasi status) {
    Color bg = const Color(0xFFFEF3C7);
    Color text = const Color(0xFFD97706);

    if (status == StatusRekomendasi.disetujui) {
      bg = AppTheme.lightGreenBg;
      text = AppTheme.accentGreen;
    } else if (status == StatusRekomendasi.ditolak) {
      bg = const Color(0xFFFEF2F2);
      text = const Color(0xFFDC2626);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(status.name.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: text)),
    );
  }

  // TAB 3: Deteksi Anomali
  Widget _buildDeteksiAnomaliTab(BuildContext context, bool isMobile) {
    final ai = context.watch<AiSuiteProvider>();
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
      itemCount: ai.daftarAnomali.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final a = ai.daftarAnomali[index];
        final isTinggi = a.tingkatKeparahan == 'TINGGI';

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: a.isDiselesaikan ? AppTheme.cardBorder : (isTinggi ? const Color(0xFFFECACA) : const Color(0xFFFDE68A))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: isTinggi ? const Color(0xFFDC2626) : const Color(0xFFD97706), size: 22),
                      const SizedBox(width: 8),
                      Text(a.judul, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: a.isDiselesaikan ? AppTheme.lightGreenBg : (isTinggi ? const Color(0xFFFEF2F2) : const Color(0xFFFEF3C7)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      a.isDiselesaikan ? 'SELESAI DITELUSURI' : 'KEPARAHAN: ${a.tingkatKeparahan}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: a.isDiselesaikan ? AppTheme.accentGreen : (isTinggi ? const Color(0xFFDC2626) : const Color(0xFFD97706)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Kasus: ${a.unitKasus} vs Pembanding: ${a.unitPembanding}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
              const SizedBox(height: 8),
              Text(a.deskripsi, style: const TextStyle(fontSize: 13, height: 1.45, color: AppTheme.textPrimary)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Potensi Kebocoran: ${a.potensiKerugian} • Terdeteksi: ${dateFormat.format(a.waktuDeteksi)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                  if (!a.isDiselesaikan)
                    ElevatedButton.icon(
                      onPressed: () {
                        ai.selesaikanAnomali(a.id);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kasus anomali ditandai telah ditelusuri & ditindaklanjuti.')));
                      },
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Tindak Lanjuti'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // TAB 4: Simulasi What-If Alokasi Modal
  Widget _buildWhatIfSimulasiTab(BuildContext context, bool isMobile) {
    final ai = context.watch<AiSuiteProvider>();

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Simulasi What-If Alokasi Modal Lintas Cabang', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 4),
          const Text('Uji skenario persentase surplus kas yang dialihkan ke unit berkembang dan lihat proyeksi kenaikan omzetnya.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(22),
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
                    const Text('Unit Sumber Surplus (Cash Cow):', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    const Text('Laundry Bersih Kilat (Surplus Kas: Rp 16.600.000)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Unit Penerima Investasi:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    const Text('Toko Elektronik Digital (Question Mark)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryBlue)),
                  ],
                ),
                const Divider(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Pilih Persentase Surplus Kas Dialihkan:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('${ai.persenAlokasiSurplus.toInt()}% (${currency.format(ai.modalDialokasikan)})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.primaryBlue)),
                  ],
                ),
                Slider(
                  value: ai.persenAlokasiSurplus,
                  min: 5,
                  max: 50,
                  divisions: 9,
                  activeColor: AppTheme.primaryBlue,
                  onChanged: (val) => ai.setPersenAlokasi(val),
                ),
                const SizedBox(height: 16),
                // Hasil Simulasi What-If
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.lightGreenBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.insights_rounded, color: AppTheme.accentGreen, size: 20),
                          SizedBox(width: 8),
                          Text('Hasil Simulasi AI & Proyeksi Dampak Bisnis:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.accentGreen)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Modal Baru Disuntikkan:'),
                          Text(currency.format(ai.modalDialokasikan), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Proyeksi Kenaikan Omzet Unit Penerima:'),
                          Text('+${currency.format(ai.proyeksiKenaikanOmzetPenerima)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentGreen)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Estimasi Laju Pertumbuhan Baru:'),
                          Text('+${ai.proyeksiPertumbuhanPersenPenerima.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Alokasi modal ${ai.persenAlokasiSurplus.toInt()}% (${currency.format(ai.modalDialokasikan)}) disetujui & dicatat ke rencana anggaran!')),
                      );
                    },
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Eksekusi Skenario Alokasi Modal'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
