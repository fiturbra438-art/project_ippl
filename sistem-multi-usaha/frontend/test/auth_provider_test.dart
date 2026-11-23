import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_multi_usaha/models/user_model.dart';
import 'package:frontend_multi_usaha/providers/auth_provider.dart';

Map<String, dynamic> _row({
  int id = 7,
  String nama = 'Budi',
  String peran = 'kasir',
  List<int> units = const [1],
  bool aktif = true,
}) =>
    {
      'id': id,
      'nama': nama,
      'email': 'budi@example.com',
      'peran': peran,
      'unit_akses_ids': units,
      'is_active': aktif,
    };

Future<AuthProvider> _seeded({
  ApiPut? put,
  ApiDelete? delete,
}) async {
  final provider = AuthProvider(
    get: (_) async => {
      'status': 'success',
      'data': [_row()],
    },
    put: put,
    delete: delete,
  );
  await provider.loadPengguna();
  return provider;
}

void main() {
  test('loadPengguna maps backend fields into penggunaList', () async {
    final provider = await _seeded();
    expect(provider.penggunaList.length, 1);
    final u = provider.penggunaList.first;
    expect(u.id, 7);
    expect(u.role, UserRole.kasir);
    expect(u.unitAksesIds, [1]);
    expect(u.isAktif, isTrue);
  });

  test('updatePenggunaAkses commits only after success', () async {
    final pending = Completer<Map<String, dynamic>?>();
    final provider = await _seeded(put: (_, __) => pending.future);

    final future = provider.updatePenggunaAkses(
      id: 7,
      nama: 'Budi Baru',
      role: UserRole.manager,
      unitAksesIds: [2, 3],
      isAktif: false,
    );
    expect(provider.penggunaList.first.nama, 'Budi');

    pending.complete({'status': 'success'});
    expect(await future, isTrue);
    final u = provider.penggunaList.first;
    expect(u.nama, 'Budi Baru');
    expect(u.role, UserRole.manager);
    expect(u.unitAksesIds, [2, 3]);
    expect(u.isAktif, isFalse);
  });

  test('updatePenggunaAkses failure keeps old data and reports error',
      () async {
    final provider = await _seeded(
      put: (_, __) async => {'status': 'error', 'message': 'Ditolak server'},
    );

    final ok = await provider.updatePenggunaAkses(
      id: 7,
      nama: 'Tidak Tersimpan',
      role: UserRole.auditor,
      unitAksesIds: [9],
      isAktif: false,
    );
    expect(ok, isFalse);
    expect(provider.lastError, 'Ditolak server');
    final u = provider.penggunaList.first;
    expect(u.nama, 'Budi');
    expect(u.role, UserRole.kasir);
  });

  test('hapusPengguna deletes locally only after success', () async {
    final provider = await _seeded(
      delete: (_) async => {'status': 'success'},
    );
    expect(await provider.hapusPengguna(7), isTrue);
    expect(provider.penggunaList, isEmpty);
  });

  test('hapusPengguna failure keeps pengguna and reports error', () async {
    final provider = await _seeded(
      delete: (_) async => {'status': 'error', 'message': 'Gagal hapus'},
    );
    expect(await provider.hapusPengguna(7), isFalse);
    expect(provider.penggunaList.length, 1);
    expect(provider.lastError, 'Gagal hapus');
  });

  test('toggleStatusPengguna flips only on success', () async {
    var fail = true;
    final provider = await _seeded(
      put: (_, __) async => fail
          ? {'status': 'error', 'message': 'Gagal status'}
          : {'status': 'success'},
    );

    expect(await provider.toggleStatusPengguna(7), isFalse);
    expect(provider.penggunaList.first.isAktif, isTrue);

    fail = false;
    expect(await provider.toggleStatusPengguna(7), isTrue);
    expect(provider.penggunaList.first.isAktif, isFalse);
  });
}
