use serde::{Deserialize, Serialize};
use crate::models::{PaketLangganan, PeranPengguna};

// ==================== OWNER AUTH SCHEMAS ====================

#[derive(Debug, Deserialize)]
pub struct RegisterOwnerRequest {
    pub nama: String,
    pub email: String,
    pub password: String,
    pub nama_bisnis_induk: String,
}

#[derive(Debug, Deserialize)]
pub struct LoginOwnerRequest {
    pub email: String,
    pub password: String,
}

#[derive(Debug, Deserialize)]
pub struct Verify2FARequest {
    pub email: String,
    pub code_otp: String,
}

#[derive(Debug, Serialize)]
pub struct OwnerAuthResponse {
    pub token: String,
    pub owner_id: i64,
    pub nama: String,
    pub email: String,
    pub nama_bisnis: String,
    pub paket: PaketLangganan,
    pub kuota_unit_usaha: i32,
    pub sisa_kuota_ai: i32,
}

#[derive(Debug, Deserialize)]
pub struct UpgradeTierRequest {
    pub paket_baru: PaketLangganan,
}

// ==================== KARYAWAN AUTH SCHEMAS ====================

#[derive(Debug, Deserialize)]
pub struct LoginKaryawanRequest {
    pub email: String,
    pub password: String,
    pub unit_id_pilihan: Option<i64>, // Karyawan bisa langsung memilih unit usaha saat login
}

#[derive(Debug, Serialize)]
pub struct KaryawanAuthResponse {
    pub token: String,
    pub karyawan_id: i64,
    pub nama: String,
    pub email: String,
    pub peran: PeranPengguna,
    pub owner_id: i64,
    pub unit_akses_ids: Vec<i64>,
}

#[derive(Debug, Serialize)]
pub struct ApiResponse<T> {
    pub status: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>,
}
