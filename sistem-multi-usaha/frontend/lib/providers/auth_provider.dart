import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

typedef ApiGet = Future<Map<String, dynamic>?> Function(String endpoint);
typedef ApiPut = Future<Map<String, dynamic>?> Function(
    String endpoint, Map<String, dynamic> body);
typedef ApiDelete = Future<Map<String, dynamic>?> Function(String endpoint);

class AuthProvider extends ChangeNotifier {
  AuthProvider({ApiGet? get, ApiPut? put, ApiDelete? delete})
      : _get = get ?? ApiService.get,
        _put = put ?? ApiService.put,
        _delete = delete ?? ApiService.delete;

  final ApiGet _get;
  final ApiPut _put;
  final ApiDelete _delete;

  UserModel? _currentUser;

  int? _selectedUnitId; // null = semua unit (konsolidasi owner)
  bool _isAwaiting2FA = false;
  String _tempEmail = '';
  String _tempPassword = '';
  String? _lastError;

  // Daftar pengguna yang disinkronkan dengan backend
  final List<UserModel> _penggunaList = [];

  final List<AuditLogModel> _auditLogs = [];

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAwaiting2FA => _isAwaiting2FA;
  int? get selectedUnitId => _selectedUnitId;
  String? get lastError => _lastError;
  List<UserModel> get penggunaList => _penggunaList;
  List<AuditLogModel> get auditLogs => _auditLogs;

  // Cek apakah pengguna saat ini berhak mengatur harga modal & harga jual (Hanya Manager & Owner)
  bool get canManagePrices {
    if (_currentUser == null) return false;
    return _currentUser!.role == UserRole.owner || _currentUser!.role == UserRole.manager;
  }

  // Cek apakah pengguna berhak membuka dashboard konsolidasi owner
  bool get isOwner {
    return _currentUser?.role == UserRole.owner;
  }

  void setSelectedUnit(int? unitId) {
    _selectedUnitId = unitId;
    notifyListeners();
  }

  Future<bool> initiateLogin(String email, String password) async {
    _lastError = null;
    // 1. Coba login via backend Rust API
    try {
      final resOwner = await AuthService.loginOwner(email, password);
      if (resOwner != null) {
        if (resOwner['status'] == 'require_2fa') {
          _tempEmail = email;
          _tempPassword = password;
          _isAwaiting2FA = true;
          notifyListeners();
          return true;
        } else if (resOwner['status'] == 'success') {
          final data = resOwner['data'];
          _currentUser = UserModel(
            id: (data['owner_id'] as num?)?.toInt() ?? 1,
            nama: data['nama'] as String? ?? email,
            email: email,
            role: UserRole.owner,
            unitAksesIds: [],
            is2FAAktif: true,
          );
          _isAwaiting2FA = false;
          notifyListeners();
          return true;
        }
      }

      // 2. Jika bukan owner, coba login sebagai karyawan
      final resKaryawan = await AuthService.loginKaryawan(email: email, password: password);
      if (resKaryawan != null && resKaryawan['status'] == 'success') {
        final data = resKaryawan['data'];
        final peranStr = data['peran'] as String? ?? 'kasir';
        final roleEnum = matchRoleFromString(peranStr);

        // Platform Guard: Pada Web, izinkan Owner, Manager, dan Admin Gudang
        if (kIsWeb && roleEnum != UserRole.manager && roleEnum != UserRole.owner && roleEnum != UserRole.adminGudang) {
          ApiService.authToken = null;
          _lastError = 'Akses Web tidak diizinkan untuk peran ini.';
          notifyListeners();
          return false;
        }

        final unitIds = (data['unit_akses_ids'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [];

        _currentUser = UserModel(
          id: (data['karyawan_id'] as num?)?.toInt() ?? 2,
          nama: data['nama'] as String? ?? email,
          email: email,
          role: roleEnum,
          unitAksesIds: unitIds,
          isAktif: true,
        );
        _isAwaiting2FA = false;
        notifyListeners();
        return true;
      }

      _lastError = (resKaryawan?['message'] as String?) ??
          (resOwner?['message'] as String?) ??
          'Email atau password tidak sesuai.';
    } catch (e) {
      debugPrint('AuthProvider.initiateLogin error: $e');
      _lastError = 'Gagal memproses login: $e';
      notifyListeners();
      return false;
    }

    notifyListeners();
    return false;
  }

  UserRole matchRoleFromString(String str) {
    switch (str.toLowerCase()) {
      case 'manager':
        return UserRole.manager;
      case 'admin_gudang':
        return UserRole.adminGudang;
      case 'auditor':
        return UserRole.auditor;
      default:
        return UserRole.kasir;
    }
  }

  Future<bool> verify2FACode(String code) async {
    _lastError = null;
    try {
      final res = await AuthService.verify2FA(_tempEmail, _tempPassword, code);
      if (res != null && res['status'] == 'success') {
        final data = res['data'];
        _currentUser = UserModel(
          id: (data['owner_id'] as num?)?.toInt() ?? 1,
          nama: data['nama'] as String? ?? _tempEmail,
          email: _tempEmail,
          role: UserRole.owner,
          unitAksesIds: [],
          is2FAAktif: true,
        );
        _isAwaiting2FA = false;
        addAuditLog('LOGIN_2FA', 'AUTH', _tempEmail, 'Login Owner berhasil dengan verifikasi 2FA');
        notifyListeners();
        return true;
      }
      _lastError = res?['message'] as String? ?? 'Kode OTP tidak valid.';
    } catch (e) {
      debugPrint('AuthProvider.verify2FACode error: $e');
      _lastError = 'Gagal memverifikasi 2FA: $e';
    }

    notifyListeners();
    return false;
  }

  Future<bool> registerOwner({
    required String nama,
    required String email,
    required String password,
    required String namaUsahaUtama,
  }) async {
    _lastError = null;
    try {
      final res = await AuthService.registerOwner(
        nama: nama,
        email: email,
        password: password,
        namaBisnisInduk: namaUsahaUtama,
      );
      if (res != null) {
        if (res['status'] == 'require_2fa') {
          _tempEmail = email;
          _tempPassword = password;
          _isAwaiting2FA = true;
          addAuditLog('REGISTER_OWNER', 'AUTH', email, 'Registrasi akun Owner berhasil. Menunggu verifikasi OTP.');
          notifyListeners();
          return true;
        } else if (res['status'] == 'success') {
          final data = res['data'];
          _currentUser = UserModel(
            id: (data['owner_id'] as num?)?.toInt() ?? 1,
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
        _lastError = res['message'] as String? ?? 'Gagal mendaftarkan akun Owner.';
      }
    } catch (e) {
      debugPrint('AuthProvider.registerOwner error: $e');
      _lastError = 'Gagal registrasi Owner: $e';
    }

    notifyListeners();
    return false;
  }

  // Daftarkan karyawan dengan password ke PostgreSQL backend
  Future<String?> tambahKaryawanKeBackend({
    required String nama,
    required String email,
    required String password,
    required UserRole role,
    required List<int> unitAksesIds,
  }) async {
    String roleStr;
    switch (role) {
      case UserRole.manager:
        roleStr = 'manager';
        break;
      case UserRole.adminGudang:
        roleStr = 'admin_gudang';
        break;
      case UserRole.auditor:
        roleStr = 'auditor';
        break;
      default:
        roleStr = 'kasir';
    }

    try {
      final res = await ApiService.post('/karyawan', {
        'nama': nama,
        'email': email,
        'password': password,
        'peran': roleStr,
        'unit_akses_ids': unitAksesIds,
      });

      if (res != null) {
        if (res['status'] == 'success') {
          final newId = (res['data']?['id'] as num?)?.toInt();
          if (newId == null) {
            debugPrint('AuthProvider.tambahKaryawanKeBackend: ID karyawan tidak dikembalikan oleh server.');
            return 'Server tidak mengembalikan ID karyawan yang valid.';
          }
          _penggunaList.add(UserModel(
            id: newId,
            nama: nama,
            email: email,
            role: role,
            unitAksesIds: unitAksesIds,
          ));
          addAuditLog('TAMBAH_KARYAWAN', 'PENGGUNA', email, 'Owner mendaftarkan karyawan $roleStr dengan password resmi');
          notifyListeners();
          return null; // Sukses tanpa error
        } else {
          return res['message'] as String? ?? 'Gagal mendaftarkan karyawan.';
        }
      }
    } catch (e) {
      debugPrint('AuthProvider.tambahKaryawanKeBackend error: $e');
      return 'Terjadi kendala jaringan: $e';
    }

    return 'Gagal terhubung ke backend server.';
  }

  void logout() {
    if (_currentUser != null) {
      addAuditLog('LOGOUT', 'AUTH', _currentUser!.email, 'User keluar dari sesi aplikasi');
    }
    _currentUser = null;
    _isAwaiting2FA = false;
    _selectedUnitId = null;
    _lastError = null;
    ApiService.authToken = null;
    notifyListeners();
  }

  void tambahPengguna(UserModel user) {
    _penggunaList.add(user);
    addAuditLog('TAMBAH_PENGGUNA', 'PENGGUNA', user.email, 'Owner menetapkan role ${user.role.label} pada unit ${user.unitAksesIds}');
    notifyListeners();
  }

  Future<void> loadPengguna() async {
    final res = await _get('/karyawan');
    if (res?['status'] != 'success' || res?['data'] is! List) {
      _lastError = res?['message'] as String? ?? 'Gagal memuat pengguna.';
      notifyListeners();
      return;
    }
    _penggunaList
      ..clear()
      ..addAll((res!['data'] as List).map((raw) {
        final data = Map<String, dynamic>.from(raw as Map);
        return UserModel(
          id: (data['id'] as num).toInt(),
          nama: data['nama'] as String? ?? '',
          email: data['email'] as String? ?? '',
          role: matchRoleFromString(data['peran'] as String? ?? 'kasir'),
          unitAksesIds: (data['unit_akses_ids'] as List? ?? []).map((e) => (e as num).toInt()).toList(),
          isAktif: data['is_active'] as bool? ?? true,
        );
      }));
    notifyListeners();
  }

  Future<bool> updatePenggunaAkses({
    required int id, required String nama, required UserRole role,
    required List<int> unitAksesIds, required bool isAktif,
  }) async {
    final idx = _penggunaList.indexWhere((u) => u.id == id);
    if (idx == -1) return false;
    final isManager = _currentUser?.role == UserRole.manager;
    final payload = <String, dynamic>{
      'nama': nama,
      'unit_akses_ids': unitAksesIds,
    };
    if (!isManager) {
      payload['peran'] = role.name == 'adminGudang' ? 'admin_gudang' : role.name;
      payload['is_active'] = isAktif;
    }
    final res = await _put('/karyawan/$id', payload);
    if (res?['status'] != 'success') { _lastError = res?['message'] as String? ?? 'Gagal memperbarui pengguna.'; notifyListeners(); return false; }
    final old = _penggunaList[idx];
    _penggunaList[idx] = UserModel(
      id: id,
      nama: nama,
      email: old.email,
      role: isManager ? old.role : role,
      unitAksesIds: unitAksesIds,
      isAktif: isManager ? old.isAktif : isAktif,
      is2FAAktif: old.is2FAAktif,
    );
    notifyListeners();
    return true;
  }

  Future<bool> hapusPengguna(int id) async {
    final idx = _penggunaList.indexWhere((u) => u.id == id);
    if (idx == -1) return false;
    final res = await _delete('/karyawan/$id');
    if (res?['status'] != 'success') { _lastError = res?['message'] as String? ?? 'Gagal menghapus pengguna.'; notifyListeners(); return false; }
    _penggunaList.removeAt(idx);
    notifyListeners();
    return true;
  }

  Future<bool> toggleStatusPengguna(int id) async {
    final idx = _penggunaList.indexWhere((u) => u.id == id);
    if (idx == -1) return false;
    final u = _penggunaList[idx];
    return updatePenggunaAkses(id: id, nama: u.nama, role: u.role, unitAksesIds: u.unitAksesIds, isAktif: !u.isAktif);
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
