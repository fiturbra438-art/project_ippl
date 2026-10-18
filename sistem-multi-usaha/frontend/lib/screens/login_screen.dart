import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_navigator.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isRegisterMode = false;
  final _emailCtrl = TextEditingController(text: 'owner@multi-usaha.com');
  final _passwordCtrl = TextEditingController(text: '123456');
  final _namaCtrl = TextEditingController(text: 'Budi Santoso');
  final _usahaCtrl = TextEditingController(text: 'Kopi & Retail Group');
  final _otpCtrl = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  void _handleAction() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);

    if (auth.isAwaiting2FA) {
      final ok = await auth.verify2FACode(_otpCtrl.text);
      if (mounted) {
        setState(() => _isLoading = false);
        if (ok) {
          AppNavigator.pushReplacementFullscreen(context, const DashboardScreen());
        } else {
          setState(() => _errorMessage = 'Kode 2FA salah atau kurang dari 4 digit.');
        }
      }
      return;
    }

    if (_isRegisterMode) {
      if (_namaCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _passwordCtrl.text.length < 6) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Lengkapi seluruh data dan password minimal 6 karakter.';
        });
        return;
      }
      final ok = await auth.registerOwner(
        nama: _namaCtrl.text,
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        namaUsahaUtama: _usahaCtrl.text,
      );
      if (mounted) {
        setState(() => _isLoading = false);
        if (ok) {
          AppNavigator.pushReplacementFullscreen(context, const DashboardScreen());
        }
      }
    } else {
      final ok = await auth.initiateLogin(_emailCtrl.text, _passwordCtrl.text);
      if (mounted) {
        setState(() => _isLoading = false);
        if (ok) {
          if (!auth.isAwaiting2FA) {
            AppNavigator.pushReplacementFullscreen(context, const DashboardScreen());
          }
        } else {
          setState(() => _errorMessage = 'Email atau password salah (minimal 6 karakter).');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: isMobile ? AppTheme.surfaceWhite : AppTheme.backgroundLight,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: EdgeInsets.all(isMobile ? 12 : 36),
              decoration: isMobile
                  ? null
                  : BoxDecoration(
                      color: AppTheme.surfaceWhite,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.cardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(10),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.lightBlueBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        auth.isAwaiting2FA ? Icons.security_rounded : Icons.hub_rounded,
                        size: 36,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      auth.isAwaiting2FA
                          ? 'Verifikasi 2 Faktor (2FA)'
                          : (_isRegisterMode ? 'Registrasi Akun Owner' : 'MultiUsaha Login'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      auth.isAwaiting2FA
                          ? 'Masukkan 6-digit kode verifikasi keamanan akun Owner'
                          : (_isRegisterMode
                              ? 'Buat akun pemilik bisnis multi-cabang'
                              : 'Sistem Manajemen Multi-Usaha Terintegrasi AI'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (auth.isAwaiting2FA) ...[
                    const Text('Kode OTP / Token Authenticator', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _otpCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      style: const TextStyle(letterSpacing: 10, fontSize: 24, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: '123456',
                        counterText: '',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tip demo: Masukkan sembarang 6 angka (misal: 123456)',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ] else ...[
                    if (_isRegisterMode) ...[
                      const Text('Nama Lengkap Pemilik', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _namaCtrl,
                        decoration: InputDecoration(
                          hintText: 'Nama lengkap Anda',
                          prefixIcon: const Icon(Icons.person_outline, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('Nama Bisnis / Perusahaan Induk', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _usahaCtrl,
                        decoration: InputDecoration(
                          hintText: 'Misal: PT Aneka Sukses',
                          prefixIcon: const Icon(Icons.business_outlined, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const Text('Email Akun', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailCtrl,
                      decoration: InputDecoration(
                        hintText: 'nama@multi-usaha.com',
                        prefixIcon: const Icon(Icons.email_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Kata Sandi', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              auth.isAwaiting2FA
                                  ? 'Verifikasi & Masuk'
                                  : (_isRegisterMode ? 'Daftar Akun Owner' : 'Masuk ke Sistem'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                    ),
                  ),
                  if (!auth.isAwaiting2FA) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            _isRegisterMode = !_isRegisterMode;
                            _errorMessage = null;
                          });
                        },
                        child: Text(
                          _isRegisterMode
                              ? 'Sudah punya akun? Masuk di sini'
                              : 'Belum punya akun? Daftar sebagai Owner',
                          style: const TextStyle(color: AppTheme.primaryBlue, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: () => auth.logout(),
                        child: const Text('Batal & Masuk dengan akun lain', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
