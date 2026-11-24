import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_multi_usaha/services/csv_import_service.dart';

void main() {
  test('parses valid CSV with header and quoted name', () {
    const csv = 'SKU,Nama,Harga Beli,Harga Jual,Stok\n'
        'A1,"Kopi, Arabika",10000,15000,20\n'
        'B2,Teh,5000,8000,10,3\n';
    final result = parseProdukCsv(csv);
    expect(result.errors, isEmpty);
    expect(result.rows.length, 2);
    expect(result.rows.first.nama, 'Kopi, Arabika');
    expect(result.rows.last.minStok, 3);
  });

  test('rejects malformed and duplicate rows', () {
    const csv = 'SKU,Nama,Harga Beli,Harga Jual,Stok\n'
        'A1,Kopi,10000,15000,20\n'
        'A1,Kopi Dua,10000,15000,5\n'
        'B2,Teh,-1,8000,10\n'
        'C3,Susu,1000,2000\n';
    final result = parseProdukCsv(csv);
    expect(result.rows.length, 1);
    expect(result.errors.length, 3);
  });

  test('parses indonesian thousand separators', () {
    const csv = 'A1,Kopi,10.000,15.000,5\n';
    final result = parseProdukCsv(csv);
    expect(result.errors, isEmpty);
    expect(result.rows.single.hargaBeli, 10000);
    expect(result.rows.single.hargaJual, 15000);
  });
}
