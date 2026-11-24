import '../models/laporan.dart';
import 'csv_download_stub.dart'
    if (dart.library.html) 'csv_download_web.dart' as platform;

String _field(Object? value) {
  final text = value?.toString() ?? '';
  if (text.contains(',') || text.contains('"') || text.contains('\n')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

String buildLaporanCsv(
  LaporanSummary summary, {
  String? periode,
  String? unit,
}) {
  final lines = <String>[
    ['Laporan Keuangan', periode ?? 'Semua periode', unit ?? 'Semua unit'].map(_field).join(','),
    '',
    ['Ringkasan', 'Nilai'].map(_field).join(','),
    ['Total Pemasukan', summary.totalPemasukan].map(_field).join(','),
    ['Total Pengeluaran', summary.totalPengeluaran].map(_field).join(','),
    ['Omzet Kotor', summary.omzetKotor].map(_field).join(','),
    ['Diskon', summary.diskon].map(_field).join(','),
    ['Refund', summary.refund].map(_field).join(','),
    ['Omzet Bersih', summary.omzetBersih].map(_field).join(','),
    ['HPP', summary.hpp].map(_field).join(','),
    ['Laba Operasional', summary.labaOperasional].map(_field).join(','),
    ['Margin Laba (%)', summary.marginLabaPersen].map(_field).join(','),
    '',
    ['Rincian Pengeluaran', 'Nominal', 'Persen'].map(_field).join(','),
    ...summary.rincianPengeluaran.map(
      (item) => [item.nama, item.nominal, item.persen].map(_field).join(','),
    ),
    '',
    ['Performa Unit', 'Pendapatan', 'Pengeluaran', 'Laba Bersih', 'Kontribusi (%)']
        .map(_field)
        .join(','),
    ...summary.performaUnit.map(
      (unit) => [
        unit.namaUnit,
        unit.pendapatan,
        unit.pengeluaran,
        unit.labaBersih,
        unit.kontribusiPersen,
      ].map(_field).join(','),
    ),
  ];
  return lines.join('\n');
}

void exportLaporanCsv(String filename, String content) {
  platform.downloadCsv(filename, content);
}
