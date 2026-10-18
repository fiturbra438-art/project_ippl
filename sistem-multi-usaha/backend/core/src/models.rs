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
    Free,       // Maksimal 2 unit usaha, AI terbatas (20 kredit)
    Pro,        // Maksimal 5 unit usaha, AI forecasting & realokasi stok (250 kredit)
    Enterprise, // Unlimited unit usaha, AI full suite + BI Chatbot + Deteksi Anomali (99999 kredit)
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

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    pub sub: String,          // email
    pub user_id: i64,
    pub role: String,         // owner / manager / kasir / admin_gudang / auditor
    pub owner_id: i64,        // id bisnis induk
    pub tier: Option<String>, // free / pro / enterprise (khusus owner)
    pub exp: usize,
}

// ==================== MODUL UNIT USAHA ====================
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsahaModel {
    pub id: i64,
    pub owner_id: i64,
    pub nama: String,
    pub jenis_usaha: String,
    pub lokasi: String,
    pub kategori_portofolio: String, // Star, Cash Cow, Question Mark, Dog
    pub pendapatan_bulan_ini: f64,
    pub pengeluaran_bulan_ini: f64,
    pub pertumbuhan_persen: f64,
    pub status: bool,
    pub has_pos: bool, // true = kafe/retail dg kasir POS, false = gudang/grosir murni
}

// ==================== MODUL PRODUK & STOK ====================
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProdukModel {
    pub id: i64,
    pub owner_id: i64,
    pub unit_id: i64,
    pub nama: String,
    pub sku: String,
    pub harga_beli: f64,
    pub harga_jual: f64,
    pub stok: i32,
    pub min_stok: i32,
}

// ==================== MODUL TRANSAKSI & POS ====================
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum JenisTransaksi {
    Pemasukan,
    Pengeluaran,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ItemCheckout {
    pub produk_id: i64,
    pub nama_produk: String,
    pub harga_satuan: f64,
    pub jumlah: i32,
    pub subtotal: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransaksiModel {
    pub id: i64,
    pub owner_id: i64,
    pub unit_id: i64,
    pub nama_unit: String,
    pub tanggal: String,
    pub jenis: JenisTransaksi,
    pub kategori: String,
    pub jumlah: f64,
    pub keterangan: String,
    pub metode_pembayaran: Option<String>, // Tunai, QRIS, Transfer Bank
    pub items: Option<Vec<ItemCheckout>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum StatusShift {
    Open,
    Closed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShiftKasirModel {
    pub id: i64,
    pub unit_id: i64,
    pub kasir_id: i64,
    pub nama_kasir: String,
    pub modal_awal: f64,
    pub total_penjualan_tunai: f64,
    pub total_penjualan_non_tunai: f64,
    pub total_transaksi: i32,
    pub waktu_buka: String,
    pub waktu_tutup: Option<String>,
    pub status: StatusShift,
}

// ==================== MODUL GUDANG & PERMINTAAN STOK ====================
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum StatusPermintaanStok {
    Pending,
    Disetujui,
    Ditolak,
    Selesai,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PermintaanStokModel {
    pub id: i64,
    pub owner_id: i64,
    pub unit_id: i64,
    pub nama_unit: String,
    pub pemohon: String,
    pub nama_produk: String,
    pub jumlah_diminta: i32,
    pub alasan: String,
    pub waktu_pengajuan: String,
    pub status: StatusPermintaanStok,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StokOpnameModel {
    pub id: i64,
    pub owner_id: i64,
    pub unit_id: i64,
    pub nama_unit: String,
    pub nama_produk: String,
    pub stok_sistem: i32,
    pub stok_fisik: i32,
    pub selisih: i32,
    pub alasan: String,
    pub tanggal: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum StatusTransfer {
    Pending,
    Diterima,
    Ditolak,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferStokModel {
    pub id: i64,
    pub owner_id: i64,
    pub unit_asal_id: i64,
    pub nama_unit_asal: String,
    pub unit_tujuan_id: i64,
    pub nama_unit_tujuan: String,
    pub produk_id: i64,
    pub nama_produk: String,
    pub jumlah: i32,
    pub waktu_kirim: String,
    pub waktu_terima: Option<String>,
    pub status: StatusTransfer,
}

// ==================== AUDIT LOG ====================
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditLogModel {
    pub id: i64,
    pub owner_id: i64,
    pub aktor: String,
    pub role: String,
    pub aksi: String,
    pub modul: String,
    pub target: String,
    pub detail: String,
    pub waktu: String,
}
