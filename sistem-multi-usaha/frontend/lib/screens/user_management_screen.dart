import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/usaha_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import 'dashboard_screen.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        title: const Text('Kelola Pengguna & Audit Log', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryBlue,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primaryBlue,
          tabs: const [
            Tab(icon: Icon(Icons.people_alt_rounded, size: 20), text: 'Hak Akses Pengguna'),
            Tab(icon: Icon(Icons.history_edu_rounded, size: 20), text: 'Audit Log (Immutable)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUserTab(context, isMobile),
          _buildAuditLogTab(context, isMobile),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        onPressed: () => _showTambahUserDialog(context),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Tambah User'),
      ),
    );
  }

  Widget _buildUserTab(BuildContext context, bool isMobile) {
    final auth = context.watch<AuthProvider>();
    final usahaList = context.watch<UsahaProvider>().rawDaftarUsaha;

    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
      itemCount: auth.penggunaList.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final u = auth.penggunaList[index];

        // Format nama unit usaha yang diakses
        String aksesLabel;
        if (u.role == UserRole.owner || u.role == UserRole.auditor) {
          aksesLabel = 'Seluruh Unit Usaha (Akses Penuh Bisnis)';
        } else if (u.unitAksesIds.isEmpty) {
          aksesLabel = 'Belum Ditempatkan ke Unit Usaha';
        } else {
          final unitNames = u.unitAksesIds.map((id) {
            final match = usahaList.where((usaha) => usaha.id == id);
            return match.isNotEmpty ? match.first.nama : 'Unit #$id';
          }).join(', ');
          aksesLabel = 'Ditugaskan di: $unitNames';
        }

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _getRoleBgColor(u.role),
                child: Text(
                  u.nama.isNotEmpty ? u.nama[0] : 'U',
                  style: TextStyle(fontWeight: FontWeight.bold, color: _getRoleTextColor(u.role)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(u.nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(width: 8),
                        _buildRoleBadge(u.role),
                        if (u.is2FAAktif) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppTheme.lightGreenBg, borderRadius: BorderRadius.circular(4)),
                            child: const Text('2FA ON', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentGreen)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(u.email, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.storefront_rounded, size: 14, color: AppTheme.primaryBlue),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            aksesLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: u.unitAksesIds.isEmpty && u.role != UserRole.owner && u.role != UserRole.auditor
                                  ? const Color(0xFFDC2626)
                                  : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  if (u.role != UserRole.owner) ...[
                    IconButton(
                      tooltip: 'Atur Posisi & Penempatan Unit',
                      icon: const Icon(Icons.edit_location_alt_rounded, color: AppTheme.primaryBlue),
                      onPressed: () => _showEditUserDialog(context, u),
                    ),
                    IconButton(
                      tooltip: 'Cabut Seluruh Akses',
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
                      onPressed: () => _konfirmasiHapusPengguna(context, u),
                    ),
                  ],
                  Column(
                    children: [
                      Switch(
                        value: u.isAktif,
                        activeColor: AppTheme.accentGreen,
                        onChanged: u.role == UserRole.owner ? null : (_) => auth.toggleStatusPengguna(u.id),
                      ),
                      Text(u.isAktif ? 'Aktif' : 'Nonaktif', style: TextStyle(fontSize: 11, color: u.isAktif ? AppTheme.accentGreen : AppTheme.textMuted)),
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

  Widget _buildAuditLogTab(BuildContext context, bool isMobile) {
    final auth = context.watch<AuthProvider>();
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm:ss');

    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
      itemCount: auth.auditLogs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final log = auth.auditLogs[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.lightBlueBg, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.shield_outlined, color: AppTheme.primaryBlue, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${log.aktor} (${log.role.label})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(dateFormat.format(log.waktu), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                          child: Text(log.aksi, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                        ),
                        const SizedBox(width: 6),
                        Text('Modul: ${log.modul}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(log.detail, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoleBadge(UserRole role) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _getRoleBgColor(role),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        role.label,
        style: TextStyle(color: _getRoleTextColor(role), fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _getRoleBgColor(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return const Color(0xFFEFF6FF);
      case UserRole.manager:
        return const Color(0xFFECFDF5);
      case UserRole.kasir:
        return const Color(0xFFFEF3C7);
      case UserRole.adminGudang:
        return const Color(0xFFF3E8FF);
      case UserRole.auditor:
        return const Color(0xFFFEE2E2);
    }
  }

  Color _getRoleTextColor(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return AppTheme.primaryBlue;
      case UserRole.manager:
        return AppTheme.accentGreen;
      case UserRole.kasir:
        return const Color(0xFFD97706);
      case UserRole.adminGudang:
        return const Color(0xFF7E22CE);
      case UserRole.auditor:
        return const Color(0xFFDC2626);
    }
  }

  void _konfirmasiHapusPengguna(BuildContext context, UserModel u) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cabut Akses Pengguna?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Akun "${u.nama}" (${u.email}) akan dinonaktifkan dan dihapus dari seluruh penempatan unit usaha.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () {
              context.read<AuthProvider>().hapusPengguna(u.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Akses untuk ${u.nama} berhasil dicabut.')),
              );
            },
            child: const Text('Hapus Akses'),
          ),
        ],
      ),
    );
  }

  void _showEditUserDialog(BuildContext context, UserModel user) {
    final namaCtrl = TextEditingController(text: user.nama);
    UserRole selectedRole = user.role;
    List<int> selectedUnitIds = List.from(user.unitAksesIds);
    bool isAktif = user.isAktif;

    final daftarUsaha = context.read<UsahaProvider>().rawDaftarUsaha;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.lightBlueBg, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.assignment_ind_rounded, color: AppTheme.primaryBlue, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('Atur Posisi & Penempatan Unit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Email: ${user.email}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: namaCtrl,
                    decoration: const InputDecoration(labelText: 'Nama Karyawan', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<UserRole>(
                    value: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Posisi / Peran Jabatan',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge_rounded, color: AppTheme.primaryBlue),
                    ),
                    items: [UserRole.manager, UserRole.kasir, UserRole.adminGudang, UserRole.auditor]
                        .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          selectedRole = val;
                          if (selectedRole == UserRole.auditor) {
                            selectedUnitIds.clear(); // Auditor bisa akses semua
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 18),
                  const Text('Pilih Unit Usaha yang Boleh Diakses:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  const Text('Karyawan hanya bisa membuka modul, POS, dan data di cabang yang dipilih.', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 10),

                  if (selectedRole == UserRole.auditor)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppTheme.lightGreenBg, borderRadius: BorderRadius.circular(8)),
                      child: const Text('Peran Auditor memiliki izin membaca seluruh laporan unit usaha.', style: TextStyle(fontSize: 12, color: AppTheme.accentGreen)),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.cardBorder),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: daftarUsaha.map((usaha) {
                          final isChecked = selectedUnitIds.contains(usaha.id);
                          return CheckboxListTile(
                            dense: true,
                            title: Text(usaha.nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text('${usaha.jenisUsaha} • ${usaha.lokasi}', style: const TextStyle(fontSize: 11)),
                            secondary: Icon(
                              usaha.hasPos ? Icons.point_of_sale_rounded : Icons.warehouse_rounded,
                              size: 20,
                              color: isChecked ? AppTheme.primaryBlue : AppTheme.textMuted,
                            ),
                            value: isChecked,
                            activeColor: AppTheme.primaryBlue,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  selectedUnitIds.add(usaha.id);
                                } else {
                                  selectedUnitIds.remove(usaha.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () {
                if (namaCtrl.text.trim().isEmpty) return;
                context.read<AuthProvider>().updatePenggunaAkses(
                  id: user.id,
                  nama: namaCtrl.text.trim(),
                  role: selectedRole,
                  unitAksesIds: selectedUnitIds,
                  isAktif: isAktif,
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Akses dan penempatan untuk ${user.nama} berhasil diperbarui.')),
                );
              },
              child: const Text('Simpan Perubahan'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTambahUserDialog(BuildContext context) {
    final namaCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    UserRole selectedRole = UserRole.kasir;
    List<int> selectedUnitIds = [1];
    bool obscurePassword = true;

    final daftarUsaha = context.read<UsahaProvider>().rawDaftarUsaha;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Tambah Karyawan & Tentukan Posisi', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: namaCtrl, decoration: const InputDecoration(labelText: 'Nama Lengkap *', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email Login *', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Kata Sandi / Password *',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                        onPressed: () => setState(() => obscurePassword = !obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    value: selectedRole,
                    decoration: const InputDecoration(labelText: 'Posisi / Jabatan *', border: OutlineInputBorder()),
                    items: [UserRole.manager, UserRole.kasir, UserRole.adminGudang, UserRole.auditor]
                        .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => selectedRole = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Tugaskan ke Unit Usaha (Akses Terbatas):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.cardBorder),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: daftarUsaha.map((usaha) {
                        final isChecked = selectedUnitIds.contains(usaha.id);
                        return CheckboxListTile(
                          dense: true,
                          title: Text(usaha.nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text(usaha.jenisUsaha, style: const TextStyle(fontSize: 11)),
                          value: isChecked,
                          activeColor: AppTheme.primaryBlue,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                selectedUnitIds.add(usaha.id);
                              } else {
                                selectedUnitIds.remove(usaha.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                if (namaCtrl.text.isNotEmpty && emailCtrl.text.isNotEmpty && passwordCtrl.text.isNotEmpty) {
                  if (passwordCtrl.text.length < 10) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Color(0xFFDC2626),
                        content: Text('Password minimal 10 karakter!'),
                      ),
                    );
                    return;
                  }
                  if (selectedUnitIds.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Color(0xFFDC2626),
                        content: Text('Pilih minimal 1 unit usaha yang ditugaskan!'),
                      ),
                    );
                    return;
                  }

                  final auth = Provider.of<AuthProvider>(context, listen: false);
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(ctx);

                  final errMsg = await auth.tambahKaryawanKeBackend(
                    nama: namaCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    password: passwordCtrl.text,
                    role: selectedRole,
                    unitAksesIds: selectedUnitIds,
                  );
                  navigator.pop();
                  if (errMsg == null) {
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: AppTheme.accentGreen,
                        content: Text('Akun karyawan ${emailCtrl.text} berhasil didaftarkan ke PostgreSQL!'),
                      ),
                    );
                  } else {
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFFDC2626),
                        content: Text('Gagal mendaftarkan karyawan: $errMsg'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}
