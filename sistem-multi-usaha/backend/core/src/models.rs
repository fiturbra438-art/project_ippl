use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum PeranPengguna {
    Owner,
    Manager,
    Kasir,
    AdminGudang,
    Auditor,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum PaketLangganan {
    Free,       // Maksimal 2 unit usaha, AI terbatas (10 request/hari)
    Pro,        // Maksimal 5 unit usaha, AI forecasting & realokasi stok
    Enterprise, // Unlimited unit usaha, AI full suite + BI Chatbot + Deteksi Anomali
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OwnerAccount {
    pub id: i64,
    pub nama: String,
    pub email: String,
    pub password_hash: String,
    pub nama_bisnis_induk: String,
    pub paket_langganan: PaketLangganan,
    pub kuota_unit_usaha: i32,
    pub sisa_kuota_ai: i32,
    pub is_2fa_active: bool,
    pub secret_2fa: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KaryawanAccount {
    pub id: i64,
    pub owner_id: i64, // Terikat pada owner bisnis mana
    pub nama: String,
    pub email: String,
    pub password_hash: String,
    pub peran: PeranPengguna, // manager, kasir, admin_gudang, auditor
    pub unit_akses_ids: Vec<i64>, // Unit mana saja yang boleh diakses karyawan ini
    pub is_active: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,       // email
    pub user_id: i64,
    pub role: String,      // owner / manager / kasir / dll
    pub owner_id: i64,     // pemilik bisnis
    pub tier: Option<String>, // free / pro / enterprise (khusus owner)
    pub exp: usize,
}
