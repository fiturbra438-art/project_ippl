import 'package:flutter/material.dart';
import '../models/user_model.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser = UserModel(
    id: 1,
    nama: 'Budi Santoso',
    email: 'owner@multi-usaha.com',
    role: UserRole.owner,
    unitAksesIds: [], // semua unit
    isAktif: true,
    is2FAAktif: true,
  );

  int? _selectedUnitId; // null = semua unit (konsolidasi owner)
  bool _isAwaiting2FA = false;
  String _tempEmail = '';

  final List<UserModel> _penggunaList = [
    UserModel(
      id: 1,
      nama: 'Budi Santoso (Owner)',
      email: 'owner@multi-usaha.com',
      role: UserRole.owner,
      unitAksesIds: [],
      is2FAAktif: true,
    ),
    UserModel(
      id: 2,
      nama: 'Siti Rahma',
      email: 'manager.kafe@multi-usaha.com',
      role: UserRole.manager,
      unitAksesIds: [1], // Kedai Kopi Bahagia
    ),
    UserModel(
      id: 3,
      nama: 'Andi Pratama',
      email: 'kasir.kafe@multi-usaha.com',
      role: UserRole.kasir,
      unitAksesIds: [1],
    ),
    UserModel(
      id: 4,
      nama: 'Hendra Wijaya',
      email: 'gudang@multi-usaha.com',
      role: UserRole.adminGudang,
      unitAksesIds: [1, 2, 3],
    ),
    UserModel(
      id: 5,
      nama: 'Dewi Lestari',
      email: 'auditor@multi-usaha.com',
      role: UserRole.auditor,
      unitAksesIds: [],
    ),
  ];

  final List<AuditLogModel> _auditLogs = [
    AuditLogModel(
      id: 1,
      aktor: 'Budi Santoso',
      role: UserRole.owner,
      aksi: 'UBAH_HAK_AKSES',
      modul: 'PENGGUNA',
      target: 'Siti Rahma',
      detail: 'Menambahkan akses ke unit Kedai Kopi Bahagia',
      waktu: DateTime.now().subtract(const Duration(minutes: 25)),
    ),
    AuditLogModel(
      id: 2,
      aktor: 'Siti Rahma',
      role: UserRole.manager,
      aksi: 'PERMINTAAN_STOK',
      modul: 'GUDANG',
      target: 'Biji Kopi Arabika 1kg',
      detail: 'Mengajukan restok 50 unit ke Gudang Pusat',
      waktu: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    AuditLogModel(
      id: 3,
      aktor: 'Andi Pratama',
      role: UserRole.kasir,
      aksi: 'TUTUP_SHIFT',
      modul: 'KASIR_POS',
      target: 'Shift Pagi Kedai Kopi',
      detail: 'Total laci kas Rp 1.850.000, selisih Rp 0 (Cocok)',
      waktu: DateTime.now().subtract(const Duration(hours: 4)),
    ),
    AuditLogModel(
      id: 4,
      aktor: 'Hendra Wijaya',
      role: UserRole.adminGudang,
      aksi: 'TRANSFER_STOK',
      modul: 'GUDANG',
      target: 'Fast Charger 30W',
      detail: 'Kirim 20 unit dari Gudang ke Toko Digital',
      waktu: DateTime.now().subtract(const Duration(hours: 6)),
    ),
  ];

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAwaiting2FA => _isAwaiting2FA;
  int? get selectedUnitId => _selectedUnitId;
  List<UserModel> get penggunaList => _penggunaList;
  List<AuditLogModel> get auditLogs => _auditLogs;

  void setSelectedUnit(int? unitId) {
    _selectedUnitId = unitId;
    notifyListeners();
  }

  void switchRoleForPreview(UserRole role) {
    if (_currentUser != null) {
      _currentUser = UserModel(
        id: _currentUser!.id,
        nama: _currentUser!.nama,
        email: _currentUser!.email,
        role: role,
        unitAksesIds: role == UserRole.kasir || role == UserRole.manager ? [1] : [],
        isAktif: true,
        is2FAAktif: _currentUser!.is2FAAktif,
      );
      notifyListeners();
    }
  }

  Future<bool> initiateLogin(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (email.isNotEmpty && password.length >= 6) {
      _tempEmail = email;
      // Jika email owner, trigger 2FA
      if (email.contains('owner')) {
        _isAwaiting2FA = true;
        notifyListeners();
        return true;
      }
      _currentUser = UserModel(
        id: 2,
        nama: email.split('@').first.toUpperCase(),
        email: email,
        role: UserRole.manager,
        unitAksesIds: [1],
      );
      _isAwaiting2FA = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> verify2FACode(String code) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (code.trim().length >= 4) {
      _currentUser = UserModel(
        id: 1,
        nama: _tempEmail.split('@').first.toUpperCase(),
        email: _tempEmail,
        role: UserRole.owner,
        unitAksesIds: [],
        is2FAAktif: true,
      );
      _isAwaiting2FA = false;
      addAuditLog('LOGIN_2FA', 'AUTH', _tempEmail, 'Login berhasil dengan verifikasi 2FA');
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> registerOwner({
    required String nama,
    required String email,
    required String password,
    required String namaUsahaUtama,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _currentUser = UserModel(
      id: DateTime.now().millisecondsSinceEpoch,
      nama: nama,
      email: email,
      role: UserRole.owner,
      unitAksesIds: [],
      is2FAAktif: true,
    );
    addAuditLog('REGISTER_OWNER', 'AUTH', email, 'Registrasi akun Owner baru: $namaUsahaUtama');
    notifyListeners();
    return true;
  }

  void logout() {
    if (_currentUser != null) {
      addAuditLog('LOGOUT', 'AUTH', _currentUser!.email, 'User keluar dari sesi aplikasi');
    }
    _currentUser = null;
    _isAwaiting2FA = false;
    _selectedUnitId = null;
    notifyListeners();
  }

  void tambahPengguna(UserModel user) {
    _penggunaList.add(user);
    addAuditLog('TAMBAH_PENGGUNA', 'PENGGUNA', user.email, 'Membuat user role ${user.role.label}');
    notifyListeners();
  }

  void toggleStatusPengguna(int id) {
    final idx = _penggunaList.indexWhere((u) => u.id == id);
    if (idx != -1) {
      final u = _penggunaList[idx];
      _penggunaList[idx] = UserModel(
        id: u.id,
        nama: u.nama,
        email: u.email,
        role: u.role,
        unitAksesIds: u.unitAksesIds,
        isAktif: !u.isAktif,
        is2FAAktif: u.is2FAAktif,
      );
      addAuditLog('UBAH_STATUS_PENGGUNA', 'PENGGUNA', u.email, 'Status aktif diubah menjadi ${!u.isAktif}');
      notifyListeners();
    }
  }

  void addAuditLog(String aksi, String modul, String target, String detail) {
    _auditLogs.insert(
      0,
      AuditLogModel(
        id: DateTime.now().millisecondsSinceEpoch,
        aktor: _currentUser?.nama ?? 'Sistem',
        role: _currentUser?.role ?? UserRole.owner,
        aksi: aksi,
        modul: modul,
        target: target,
        detail: detail,
        waktu: DateTime.now(),
      ),
    );
    notifyListeners();
  }
}
