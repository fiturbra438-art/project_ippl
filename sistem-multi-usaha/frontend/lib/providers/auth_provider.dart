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

  // Hanya sediakan akun Owner utama awal (Karyawan ditambahkan oleh Owner lewat UI)
  final List<UserModel> _penggunaList = [
    UserModel(
      id: 1,
      nama: 'Budi Santoso (Owner)',
      email: 'owner@multi-usaha.com',
      role: UserRole.owner,
      unitAksesIds: [],
      is2FAAktif: true,
    ),
  ];

  final List<AuditLogModel> _auditLogs = [];

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAwaiting2FA => _isAwaiting2FA;
  int? get selectedUnitId => _selectedUnitId;
  List<UserModel> get penggunaList => _penggunaList;
  List<AuditLogModel> get auditLogs => _auditLogs;

  // Cek apakah pengguna saat ini berhak mengatur harga modal & harga jual (Hanya Manager & Owner)
  bool get canManagePrices {
    if (_currentUser == null) return false;
    return _currentUser!.role == UserRole.owner || _currentUser!.role == UserRole.manager;
  }

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
    addAuditLog('TAMBAH_PENGGUNA', 'PENGGUNA', user.email, 'Owner menetapkan role ${user.role.label} pada unit ${user.unitAksesIds}');
    notifyListeners();
  }

  void updatePenggunaAkses({
    required int id,
    required String nama,
    required UserRole role,
    required List<int> unitAksesIds,
    required bool isAktif,
  }) {
    final idx = _penggunaList.indexWhere((u) => u.id == id);
    if (idx != -1) {
      _penggunaList[idx] = UserModel(
        id: id,
        nama: nama,
        email: _penggunaList[idx].email,
        role: role,
        unitAksesIds: unitAksesIds,
        isAktif: isAktif,
        is2FAAktif: _penggunaList[idx].is2FAAktif,
      );
      addAuditLog('UPDATE_HAK_AKSES', 'PENGGUNA', _penggunaList[idx].email, 'Owner memperbarui posisi menjadi ${role.label} & penempatan unit $unitAksesIds');
      notifyListeners();
    }
  }

  void hapusPengguna(int id) {
    final user = _penggunaList.firstWhere((u) => u.id == id, orElse: () => _penggunaList.first);
    _penggunaList.removeWhere((u) => u.id == id);
    addAuditLog('HAPUS_PENGGUNA', 'PENGGUNA', user.email, 'Owner mencabut seluruh akses akun');
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
