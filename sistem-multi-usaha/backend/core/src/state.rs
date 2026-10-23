use std::sync::Arc;
use tokio::sync::RwLock;
use sqlx::PgPool;
use crate::models::{
    AuditLogModel, KaryawanAccount, OwnerAccount, PaketLangganan,
    PermintaanStokModel, ProdukModel, ShiftKasirModel,
    StokOpnameModel, TransferStokModel, TransaksiModel, UsahaModel,
};
use bcrypt::hash;

pub struct AppState {
    pub db: PgPool,
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
    pub async fn new(pool: PgPool) -> Self {
        let password_demo = hash("123456", 4).unwrap_or_default();

        // 1. Tambahkan kolom owner_id pada tabel users jika belum ada (multi-tenant support)
        let _ = sqlx::query("ALTER TABLE users ADD COLUMN IF NOT EXISTS owner_id INT REFERENCES users(id) ON DELETE CASCADE")
            .execute(&pool)
            .await;

        // 1b. Sinkronisasi atau Buat Akun Owner Awal di PostgreSQL
        let owner_count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM users WHERE role = 'owner'")
            .fetch_one(&pool)
            .await
            .unwrap_or((0,));

        if owner_count.0 == 0 {
            let _ = sqlx::query(
                "INSERT INTO users (nama, email, password_hash, role, aktif, nama_perusahaan, tier, kuota_unit_usaha, sisa_kuota_ai, is_2fa_active, secret_2fa)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)"
            )
            .bind("Budi Santoso")
            .bind("owner@multi-usaha.com")
            .bind(&password_demo)
            .bind("owner")
            .bind(true)
            .bind("Aneka Makmur Group")
            .bind("pro")
            .bind(5)
            .bind(250)
            .bind(true)
            .bind("123456")
            .execute(&pool)
            .await;
        }

        // 2. Baca seluruh data nyata yang tersimpan di PostgreSQL ke cache RAM
        #[derive(sqlx::FromRow)]
        struct UserRow {
            id: i32,
            owner_id: Option<i32>,
            nama: String,
            email: String,
            password_hash: String,
            role: String,
            aktif: bool,
            nama_perusahaan: Option<String>,
            tier: Option<String>,
            kuota_unit_usaha: Option<i32>,
            sisa_kuota_ai: Option<i32>,
            is_2fa_active: Option<bool>,
            secret_2fa: Option<String>,
        }

        let user_rows: Vec<UserRow> = sqlx::query_as("SELECT id, owner_id, nama, email, password_hash, role, aktif, nama_perusahaan, tier, kuota_unit_usaha, sisa_kuota_ai, is_2fa_active, secret_2fa FROM users")
            .fetch_all(&pool)
            .await
            .unwrap_or_default();

        let mut owners: Vec<OwnerAccount> = Vec::new();
        let mut karyawans: Vec<KaryawanAccount> = Vec::new();

        for u in user_rows {
            if u.role == "owner" {
                owners.push(OwnerAccount {
                    id: u.id as i64,
                    nama: u.nama,
                    email: u.email,
                    password_hash: u.password_hash,
                    nama_bisnis_induk: u.nama_perusahaan.unwrap_or_else(|| "Grup Bisnis".to_string()),
                    paket_langganan: match u.tier.as_deref() {
                        Some("enterprise") => PaketLangganan::Enterprise,
                        Some("pro") => PaketLangganan::Pro,
                        _ => PaketLangganan::Free,
                    },
                    kuota_unit_usaha: u.kuota_unit_usaha.unwrap_or(5),
                    sisa_kuota_ai: u.sisa_kuota_ai.unwrap_or(250),
                    is_2fa_active: u.is_2fa_active.unwrap_or(true),
                    secret_2fa: u.secret_2fa,
                });
            } else {
                let peran = match u.role.as_str() {
                    "manager" => crate::models::PeranPengguna::Manager,
                    "kasir" => crate::models::PeranPengguna::Kasir,
                    "admin_gudang" => crate::models::PeranPengguna::AdminGudang,
                    _ => crate::models::PeranPengguna::Auditor,
                };

                // Ambil unit yang diakses karyawan
                let unit_ids: Vec<i64> = sqlx::query_scalar("SELECT unit_id FROM user_units WHERE user_id = $1")
                    .bind(u.id)
                    .fetch_all(&pool)
                    .await
                    .unwrap_or_default();

                let k_owner_id = u.owner_id.map(|oid| oid as i64).unwrap_or(1);

                karyawans.push(KaryawanAccount {
                    id: u.id as i64,
                    owner_id: k_owner_id,
                    nama: u.nama,
                    email: u.email,
                    password_hash: u.password_hash,
                    peran,
                    unit_akses_ids: unit_ids,
                    is_active: u.aktif,
                });
            }
        }

        // 3. Baca data Unit Usaha dari PostgreSQL
        let mut usahas: Vec<UsahaModel> = Vec::new();
        let usaha_rows = sqlx::query_as::<_, (i32, i32, String, String, Option<String>, Option<String>, bool, Option<bool>)>(
            "SELECT id, owner_id, nama, jenis_usaha, lokasi, kategori_portofolio, status, has_pos FROM business_units"
        )
        .fetch_all(&pool)
        .await
        .unwrap_or_default();

        for u in usaha_rows {
            usahas.push(UsahaModel {
                id: u.0 as i64,
                owner_id: u.1 as i64,
                nama: u.2,
                jenis_usaha: u.3,
                lokasi: u.4.unwrap_or_default(),
                kategori_portofolio: u.5.unwrap_or_else(|| "Star".to_string()),
                pendapatan_bulan_ini: 0.0,
                pengeluaran_bulan_ini: 0.0,
                pertumbuhan_persen: 0.0,
                status: u.6,
                has_pos: u.7.unwrap_or(true),
            });
        }

        let jwt_secret = std::env::var("JWT_SECRET")
            .unwrap_or_else(|_| "secret-multi-usaha-key-2026".to_string());

        Self {
            db: pool,
            owners: Arc::new(RwLock::new(owners)),
            karyawans: Arc::new(RwLock::new(karyawans)),
            usahas: Arc::new(RwLock::new(usahas)),
            produks: Arc::new(RwLock::new(Vec::new())),
            transaksis: Arc::new(RwLock::new(Vec::new())),
            shifts: Arc::new(RwLock::new(Vec::new())),
            permintaan_stoks: Arc::new(RwLock::new(Vec::new())),
            stok_opnames: Arc::new(RwLock::new(Vec::new())),
            transfer_stoks: Arc::new(RwLock::new(Vec::new())),
            audit_logs: Arc::new(RwLock::new(Vec::new())),
            jwt_secret,
        }
    }
}
