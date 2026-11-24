import 'file_picker_stub.dart'
    if (dart.library.html) 'file_picker_web.dart' as picker;

class CsvImportRow {
  final String sku;
  final String nama;
  final double hargaBeli;
  final double hargaJual;
  final int stok;
  final int? minStok;

  CsvImportRow({
    required this.sku,
    required this.nama,
    required this.hargaBeli,
    required this.hargaJual,
    required this.stok,
    this.minStok,
  });

  Map<String, dynamic> toJson() => {
        'sku': sku,
        'nama': nama,
        'harga_beli': hargaBeli,
        'harga_jual': hargaJual,
        'stok': stok,
        if (minStok != null) 'min_stok': minStok,
      };
}

class CsvParseError {
  final int baris;
  final String pesan;

  CsvParseError(this.baris, this.pesan);
}

class CsvParseResult {
  final List<CsvImportRow> rows;
  final List<CsvParseError> errors;

  CsvParseResult(this.rows, this.errors);
}

Future<String?> pickCsvFile() => picker.pickCsvText();

List<String> _splitCsvLine(String line) {
  final values = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == ',' && !inQuotes) {
      values.add(buffer.toString().trim());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  values.add(buffer.toString().trim());
  return values;
}

double? _parseAngka(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (value.contains(',')) {
    return double.tryParse(value.replaceAll('.', '').replaceAll(',', '.'));
  }
  if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(value)) {
    return double.tryParse(value.replaceAll('.', ''));
  }
  return double.tryParse(value);
}

CsvParseResult parseProdukCsv(String content) {
  final rows = <CsvImportRow>[];
  final errors = <CsvParseError>[];
  final seenSku = <String>{};
  final lines = content
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();

  var start = 0;
  if (lines.isNotEmpty) {
    final header = _splitCsvLine(lines.first).map((value) => value.toLowerCase()).toList();
    if (header.isNotEmpty && header.first == 'sku') {
      start = 1;
    }
  }

  for (var i = start; i < lines.length; i++) {
    final baris = i + 1;
    final cells = _splitCsvLine(lines[i]);
    if (cells.length < 5) {
      errors.add(CsvParseError(baris, 'Butuh minimal 5 kolom: SKU, Nama, Harga Beli, Harga Jual, Stok'));
      continue;
    }
    final sku = cells[0];
    final nama = cells[1];
    final hargaBeli = _parseAngka(cells[2]);
    final hargaJual = _parseAngka(cells[3]);
    final stok = int.tryParse(cells[4]);
    final minStok = cells.length > 5 && cells[5].isNotEmpty ? int.tryParse(cells[5]) : null;

    final pesan = <String>[];
    if (sku.isEmpty) pesan.add('SKU kosong');
    if (nama.isEmpty) pesan.add('nama kosong');
    if (hargaBeli == null || hargaBeli < 0) pesan.add('harga beli tidak valid');
    if (hargaJual == null || hargaJual < 0) pesan.add('harga jual tidak valid');
    if (stok == null || stok < 0) pesan.add('stok tidak valid');
    if (minStok != null && minStok < 0) pesan.add('min stok tidak valid');
    if (sku.isNotEmpty && !seenSku.add(sku.toLowerCase())) {
      pesan.add('SKU duplikat di file');
    }
    if (pesan.isNotEmpty) {
      errors.add(CsvParseError(baris, pesan.join(', ')));
      continue;
    }
    rows.add(CsvImportRow(
      sku: sku,
      nama: nama,
      hargaBeli: hargaBeli!,
      hargaJual: hargaJual!,
      stok: stok!,
      minStok: minStok,
    ));
  }

  if (rows.isEmpty && errors.isEmpty) {
    errors.add(CsvParseError(0, 'File CSV tidak berisi data produk.'));
  }
  return CsvParseResult(rows, errors);
}
