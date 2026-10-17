use std::sync::Arc;
use tokio::sync::RwLock;
use crate::models::{KaryawanAccount, OwnerAccount, PaketLangganan, PeranPengguna};
use bcrypt::hash;

pub struct AppState {
    pub owners: Arc<RwLock<Vec<OwnerAccount>>>,
    pub karyawans: Arc<RwLock<Vec<KaryawanAccount>>>,
    pub jwt_secret: String,
}

impl AppState {
    pub fn new() -> Self {
        let password_demo = hash("123456", 4).unwrap_or_default();

        let initial_owners = vec![
            OwnerAccount {
                id: 1,
                nama: "Budi Santoso".to_string(),
                email: "owner@multi-usaha.com".to_string(),
                password_hash: password_demo.clone(),
                nama_bisnis_induk: "Aneka Makmur Group".to_string(),
                paket_langganan: PaketLangganan::Pro,
                kuota_unit_usaha: 5,
                sisa_kuota_ai: 250,
                is_2fa_active: true,
                secret_2fa: Some("123456".to_string()),
            }
        ];

        let initial_karyawans = vec![
            KaryawanAccount {
                id: 1,
                owner_id: 1,
                nama: "Siti Rahma".to_string(),
                email: "manager@multi-usaha.com".to_string(),
                password_hash: password_demo.clone(),
                peran: PeranPengguna::Manager,
                unit_akses_ids: vec![1], // Kedai Kopi
                is_active: true,
            },
            KaryawanAccount {
                id: 2,
                owner_id: 1,
                nama: "Andi Kasir".to_string(),
                email: "kasir@multi-usaha.com".to_string(),
                password_hash: password_demo.clone(),
                peran: PeranPengguna::Kasir,
                unit_akses_ids: vec![1],
                is_active: true,
            },
            KaryawanAccount {
                id: 3,
                owner_id: 1,
                nama: "Hendra Logistik".to_string(),
                email: "gudang@multi-usaha.com".to_string(),
                password_hash: password_demo.clone(),
                peran: PeranPengguna::AdminGudang,
                unit_akses_ids: vec![1, 2, 3],
                is_active: true,
            },
            KaryawanAccount {
                id: 4,
                owner_id: 1,
                nama: "Dewi Auditor".to_string(),
                email: "auditor@multi-usaha.com".to_string(),
                password_hash: password_demo,
                peran: PeranPengguna::Auditor,
                unit_akses_ids: vec![], // Semua unit
                is_active: true,
            },
        ];

        Self {
            owners: Arc::new(RwLock::new(initial_owners)),
            karyawans: Arc::new(RwLock::new(initial_karyawans)),
            jwt_secret: "secret-multi-usaha-key-2026".to_string(),
        }
    }
}
