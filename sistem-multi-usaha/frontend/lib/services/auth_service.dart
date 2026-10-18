import 'api_service.dart';

class AuthService {
  // Login Owner -> Memicu 2FA
  static Future<Map<String, dynamic>?> loginOwner(String email, String password) async {
    return await ApiService.post('/auth/owner/login', {
      'email': email,
      'password': password,
    });
  }

  // Verifikasi 2FA Owner -> Menerima JWT Token
  static Future<Map<String, dynamic>?> verify2FA(String email, String codeOtp) async {
    final res = await ApiService.post('/auth/owner/verify-2fa', {
      'email': email,
      'code_otp': codeOtp,
    });
    if (res != null && res['status'] == 'success' && res['data'] != null) {
      final token = res['data']['token'] as String?;
      if (token != null) {
        ApiService.authToken = token;
      }
    }
    return res;
  }

  // Register Owner
  static Future<Map<String, dynamic>?> registerOwner({
    required String nama,
    required String email,
    required String password,
    required String namaBisnisInduk,
  }) async {
    final res = await ApiService.post('/auth/owner/register', {
      'nama': nama,
      'email': email,
      'password': password,
      'nama_bisnis_induk': namaBisnisInduk,
    });
    if (res != null && res['status'] == 'success' && res['data'] != null) {
      final token = res['data']['token'] as String?;
      if (token != null) {
        ApiService.authToken = token;
      }
    }
    return res;
  }

  // Login Karyawan
  static Future<Map<String, dynamic>?> loginKaryawan({
    required String email,
    required String password,
    int? unitIdPilihan,
  }) async {
    final res = await ApiService.post('/auth/karyawan/login', {
      'email': email,
      'password': password,
      'unit_id_pilihan': unitIdPilihan,
    });
    if (res != null && res['status'] == 'success' && res['data'] != null) {
      final token = res['data']['token'] as String?;
      if (token != null) {
        ApiService.authToken = token;
      }
    }
    return res;
  }
}
