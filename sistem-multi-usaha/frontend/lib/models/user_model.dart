enum UserRole {
  owner,
  manager,
  kasir,
  adminGudang,
  auditor,
}

extension UserRoleExt on UserRole {
  String get label {
    switch (this) {
      case UserRole.owner:
        return 'Owner';
      case UserRole.manager:
        return 'Manager';
      case UserRole.kasir:
        return 'Kasir';
      case UserRole.adminGudang:
        return 'Admin Gudang';
      case UserRole.auditor:
        return 'Auditor';
    }
  }
}

class UserModel {
  final int id;
  final String nama;
  final String email;
  final UserRole role;
  final List<int> unitAksesIds; // ID unit yang boleh diakses, empty = semua unit (owner/auditor)
  final bool isAktif;
  final bool is2FAAktif;

  UserModel({
    required this.id,
    required this.nama,
    required this.email,
    required this.role,
    this.unitAksesIds = const [],
    this.isAktif = true,
    this.is2FAAktif = false,
  });
}

class AuditLogModel {
  final int id;
  final String aktor;
  final UserRole role;
  final String aksi;
  final String modul;
  final String target;
  final String detail;
  final DateTime waktu;

  AuditLogModel({
    required this.id,
    required this.aktor,
    required this.role,
    required this.aksi,
    required this.modul,
    required this.target,
    required this.detail,
    required this.waktu,
  });
}
