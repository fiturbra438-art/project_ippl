use crate::models::{
    JenisTransaksi, PaketLangganan, PeranPengguna, StatusPermintaanStok, StatusTransfer,
};
use serde::{Deserialize, Serialize};

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
    pub password: String,
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

// ==================== KARYAWAN SCHEMAS ====================

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

#[derive(Debug, Deserialize)]
pub struct CreateKaryawanRequest {
    pub nama: String,
    pub email: String,
    pub password: String,
    pub peran: PeranPengguna,
    pub unit_akses_ids: Vec<i64>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateKaryawanRequest {
    pub nama: Option<String>,
    pub peran: Option<PeranPengguna>,
    pub unit_akses_ids: Option<Vec<i64>>,
    pub is_active: Option<bool>,
}

// ==================== UNIT USAHA SCHEMAS ====================

#[derive(Debug, Deserialize)]
pub struct CreateUsahaRequest {
    pub nama: String,
    pub jenis_usaha: String,
    pub lokasi: String,
    pub kategori_portofolio: Option<String>,
    pub has_pos: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateUsahaRequest {
    pub nama: Option<String>,
    pub jenis_usaha: Option<String>,
    pub lokasi: Option<String>,
    pub kategori_portofolio: Option<String>,
    pub status: Option<bool>,
    pub has_pos: Option<bool>,
}

// ==================== PRODUK SCHEMAS ====================

#[derive(Debug, Deserialize)]
pub struct CreateProdukRequest {
    pub unit_id: i64,
    pub nama: String,
    pub sku: String,
    pub harga_beli: f64,
    pub harga_jual: f64,
    pub stok: i32,
    pub min_stok: Option<i32>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateProdukRequest {
    pub nama: Option<String>,
    pub sku: Option<String>,
    pub harga_beli: Option<f64>,
    pub harga_jual: Option<f64>,
    pub stok: Option<i32>,
    pub min_stok: Option<i32>,
}

#[derive(Debug, Deserialize)]
pub struct AdjustStokRequest {
    pub penambahan: i32, // Bisa negatif untuk pengurangan manual
}

// ==================== POS & TRANSAKSI SCHEMAS ====================

#[derive(Debug, Deserialize)]
pub struct BukaShiftRequest {
    pub unit_id: i64,
    pub modal_awal: f64,
}

#[derive(Debug, Deserialize)]
pub struct TutupShiftRequest {
    pub shift_id: i64,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct CheckoutItemRequest {
    pub produk_id: i64,
    pub jumlah: i32,
    #[serde(default)]
    pub harga_satuan: Option<f64>,
}

#[derive(Debug, Deserialize)]
pub struct CheckoutRequest {
    pub unit_id: i64,
    pub items: Vec<CheckoutItemRequest>,
    pub metode_pembayaran: String, // Tunai, QRIS, Transfer Bank
    pub keterangan: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CreateTransaksiManualRequest {
    pub unit_id: i64,
    pub jenis: JenisTransaksi,
    pub kategori: String,
    pub jumlah: f64,
    pub keterangan: String,
}

// ==================== GUDANG & PERMINTAAN STOK SCHEMAS ====================

#[derive(Debug, Deserialize)]
pub struct CreatePermintaanStokRequest {
    pub unit_id: i64,
    pub nama_produk: String,
    pub jumlah_diminta: i32,
    pub alasan: String,
}

#[derive(Debug, Deserialize)]
pub struct UpdateStatusPermintaanRequest {
    pub status: StatusPermintaanStok,
}

#[derive(Debug, Deserialize)]
pub struct CreateStokOpnameRequest {
    pub unit_id: i64,
    pub nama_produk: String,
    pub stok_fisik: i32,
    pub alasan: String,
}

#[derive(Debug, Deserialize)]
pub struct CreateTransferStokRequest {
    pub unit_asal_id: i64,
    pub unit_tujuan_id: i64,
    pub produk_id: i64,
    pub jumlah: i32,
}

#[derive(Debug, Deserialize)]
pub struct UpdateStatusTransferRequest {
    pub status: StatusTransfer,
}

// ==================== DASHBOARD & AI SCHEMAS ====================

#[derive(Debug, Deserialize)]
pub struct ChatAiRequest {
    pub pesan: String,
}

#[derive(Debug, Serialize)]
pub struct ChatAiResponse {
    pub balasan: String,
    pub sumber: String,
    pub sisa_kuota_ai: i32,
}

// ==================== GENERIC API RESPONSE ====================

#[derive(Debug, Serialize)]
pub struct ApiResponse<T> {
    pub status: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>,
}
