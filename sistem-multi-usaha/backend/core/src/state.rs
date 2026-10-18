use std::sync::Arc;
use tokio::sync::RwLock;
use crate::models::{
    AuditLogModel, ItemCheckout, JenisTransaksi, KaryawanAccount, OwnerAccount, PaketLangganan,
    PeranPengguna, PermintaanStokModel, ProdukModel, ShiftKasirModel, StatusPermintaanStok,
    StatusShift, StatusTransfer, StokOpnameModel, TransferStokModel, TransaksiModel, UsahaModel,
};
use bcrypt::hash;

pub struct AppState {
    pub owners: Arc<RwLock<Vec<OwnerAccount>>>,
    pub karyawans: Arc<RwLock<Vec<KaryawanAccount>>>,
    pub usahas: Arc<RwLock<Vec<UsahaModel>>>,
    pub produks: Arc<RwLock<Vec<ProdukModel>>>,
    pub transaksis: Arc<RwLock<Vec<TransaksiModel>>>,
    pub shifts: Arc<RwLock<Vec<ShiftKasirModel>>>,
    pub permintaan_stoks: Arc<RwLock<Vec<PermintaanStokModel>>>,
    pub stok_opnames: Arc<RwLock<Vec<StokOpnameModel>>>,
    pub transfer_stoks: Arc<RwLock<Vec<TransferStokModel>>>,
    pub audit_logs: Arc<RwLock<Vec<AuditLogModel>>>,
    pub jwt_secret: String,
}

impl AppState {
    pub fn new() -> Self {
        let password_demo = hash("123456", 4).unwrap_or_default();

        // Hanya sediakan akun Owner utama awal untuk login pertama kali
        let initial_owners = vec![
            OwnerAccount {
                id: 1,
                nama: "Budi Santoso".to_string(),
                email: "owner@multi-usaha.com".to_string(),
                password_hash: password_demo,
                nama_bisnis_induk: "Aneka Makmur Group".to_string(),
                paket_langganan: PaketLangganan::Pro,
                kuota_unit_usaha: 5,
                sisa_kuota_ai: 250,
                is_2fa_active: true,
                secret_2fa: Some("123456".to_string()),
            }
        ];

        // Kosongkan seluruh data operasional (Unit Usaha, Karyawan, Produk, Transaksi, Shift, Gudang)
        let initial_karyawans: Vec<KaryawanAccount> = Vec::new();
        let initial_usahas: Vec<UsahaModel> = Vec::new();
        let initial_produks: Vec<ProdukModel> = Vec::new();
        let initial_transaksis: Vec<TransaksiModel> = Vec::new();
        let initial_shifts: Vec<ShiftKasirModel> = Vec::new();
        let initial_permintaan_stoks: Vec<PermintaanStokModel> = Vec::new();
        let initial_stok_opnames: Vec<StokOpnameModel> = Vec::new();
        let initial_transfer_stoks: Vec<TransferStokModel> = Vec::new();
        let initial_audit_logs: Vec<AuditLogModel> = Vec::new();

        Self {
            owners: Arc::new(RwLock::new(initial_owners)),
            karyawans: Arc::new(RwLock::new(initial_karyawans)),
            usahas: Arc::new(RwLock::new(initial_usahas)),
            produks: Arc::new(RwLock::new(initial_produks)),
            transaksis: Arc::new(RwLock::new(initial_transaksis)),
            shifts: Arc::new(RwLock::new(initial_shifts)),
            permintaan_stoks: Arc::new(RwLock::new(initial_permintaan_stoks)),
            stok_opnames: Arc::new(RwLock::new(initial_stok_opnames)),
            transfer_stoks: Arc::new(RwLock::new(initial_transfer_stoks)),
            audit_logs: Arc::new(RwLock::new(initial_audit_logs)),
            jwt_secret: "secret-multi-usaha-key-2026".to_string(),
        }
    }
}
