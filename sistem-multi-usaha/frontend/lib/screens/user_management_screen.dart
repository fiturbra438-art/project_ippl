import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
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

    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
      itemCount: auth.penggunaList.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final u = auth.penggunaList[index];
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
                    Text(
                      u.unitAksesIds.isEmpty
                          ? 'Akses: Seluruh Unit Usaha'
                          : 'Akses Unit: ${u.unitAksesIds.map((id) => "Unit #$id").join(", ")}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
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

  void _showTambahUserDialog(BuildContext context) {
    final namaCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    UserRole selectedRole = UserRole.kasir;
    int selectedUnitId = 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Tambah Pengguna Baru', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: namaCtrl, decoration: const InputDecoration(labelText: 'Nama Lengkap', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  value: selectedRole,
                  decoration: const InputDecoration(labelText: 'Hak Akses / Peran', border: OutlineInputBorder()),
                  items: UserRole.values.map((r) => DropdownMenuItem(value: r, child: Text(r.label))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => selectedRole = val);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: selectedUnitId,
                  decoration: const InputDecoration(labelText: 'Tugaskan ke Unit Usaha', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Kedai Kopi Bahagia')),
                    DropdownMenuItem(value: 2, child: Text('Laundry Bersih Kilat')),
                    DropdownMenuItem(value: 3, child: Text('Toko Elektronik Digital')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => selectedUnitId = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () {
                if (namaCtrl.text.isNotEmpty && emailCtrl.text.isNotEmpty) {
                  Provider.of<AuthProvider>(context, listen: false).tambahPengguna(
                    UserModel(
                      id: DateTime.now().millisecondsSinceEpoch,
                      nama: namaCtrl.text,
                      email: emailCtrl.text,
                      role: selectedRole,
                      unitAksesIds: [selectedUnitId],
                    ),
                  );
                  Navigator.pop(ctx);
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
