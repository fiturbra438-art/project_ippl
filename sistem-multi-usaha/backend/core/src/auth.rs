use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use bcrypt::{hash, verify};
use chrono::{Duration, Utc};
use jsonwebtoken::{encode, EncodingKey, Header};
use std::sync::Arc;

use crate::models::{Claims, OwnerAccount, PaketLangganan};
use crate::schemas::{
    ApiResponse, LoginKaryawanRequest, LoginOwnerRequest, OwnerAuthResponse,
    RegisterOwnerRequest, UpgradeTierRequest, Verify2FARequest, KaryawanAuthResponse,
};
use crate::state::AppState;

// Helper membuat JWT Token
fn generate_token(
    sub: &str,
    user_id: i64,
    role: &str,
    owner_id: i64,
    tier: Option<String>,
    secret: &str,
) -> Result<String, String> {
    let expiration = Utc::now()
        .checked_add_signed(Duration::days(7))
        .expect("valid timestamp")
        .timestamp() as usize;

    let claims = Claims {
        sub: sub.to_string(),
        user_id,
        role: role.to_string(),
        owner_id,
        tier,
        exp: expiration,
    };

    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .map_err(|e| e.to_string())
}

// 1. REGISTER OWNER (Hanya Owner yang bisa register mandiri)
pub async fn register_owner(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<RegisterOwnerRequest>,
) -> impl IntoResponse {
    let mut owners = state.owners.write().await;

    // Cek apakah email sudah terdaftar
    if owners.iter().any(|o| o.email.to_lowercase() == payload.email.to_lowercase()) {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<OwnerAuthResponse> {
                status: "error".to_string(),
                message: "Email sudah terdaftar sebagai pemilik usaha.".to_string(),
                data: None,
            }),
        );
    }

    let password_hash = match hash(&payload.password, 4) {
        Ok(h) => h,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<OwnerAuthResponse> {
                    status: "error".to_string(),
                    message: "Gagal mengenkripsi kata sandi.".to_string(),
                    data: None,
                }),
            );
        }
    };

    let new_id = (owners.len() as i64) + 1;
    let new_owner = OwnerAccount {
        id: new_id,
        nama: payload.nama,
        email: payload.email,
        password_hash,
        nama_bisnis_induk: payload.nama_bisnis_induk,
        paket_langganan: PaketLangganan::Free, // Default paket gratis
        kuota_unit_usaha: 2,                   // Free tier = 2 unit
        sisa_kuota_ai: 20,                     // 20 kredit AI awal
        is_2fa_active: true,                   // Owner default 2FA aktif
        secret_2fa: Some("123456".to_string()),
    };

    let token = match generate_token(
        &new_owner.email,
        new_owner.id,
        "owner",
        new_owner.id,
        Some("free".to_string()),
        &state.jwt_secret,
    ) {
        Ok(t) => t,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<OwnerAuthResponse> {
                    status: "error".to_string(),
                    message: "Gagal membuat sesi login.".to_string(),
                    data: None,
                }),
            );
        }
    };

    let res = OwnerAuthResponse {
        token,
        owner_id: new_owner.id,
        nama: new_owner.nama.clone(),
        email: new_owner.email.clone(),
        nama_bisnis: new_owner.nama_bisnis_induk.clone(),
        paket: new_owner.paket_langganan.clone(),
        kuota_unit_usaha: new_owner.kuota_unit_usaha,
        sisa_kuota_ai: new_owner.sisa_kuota_ai,
    };

    owners.push(new_owner);

    (
        StatusCode::CREATED,
        Json(ApiResponse {
            status: "success".to_string(),
            message: "Registrasi akun Owner berhasil.".to_string(),
            data: Some(res),
        }),
    )
}

// 2. LOGIN OWNER (Dengan Tantangan 2FA)
pub async fn login_owner(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<LoginOwnerRequest>,
) -> impl IntoResponse {
    let owners = state.owners.read().await;

    let owner = match owners.iter().find(|o| o.email.to_lowercase() == payload.email.to_lowercase()) {
        Some(o) => o,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(ApiResponse::<serde_json::Value> {
                    status: "error".to_string(),
                    message: "Email atau kata sandi Owner tidak cocok.".to_string(),
                    data: None,
                }),
            );
        }
    };

    if !verify(&payload.password, &owner.password_hash).unwrap_or(false) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<serde_json::Value> {
                status: "error".to_string(),
                message: "Email atau kata sandi Owner tidak cocok.".to_string(),
                data: None,
            }),
        );
    }

    // Jika 2FA aktif, kembalikan tantangan 2FA
    if owner.is_2fa_active {
        return (
            StatusCode::OK,
            Json(ApiResponse {
                status: "require_2fa".to_string(),
                message: "Verifikasi 2FA diperlukan. Masukkan kode 6 digit.".to_string(),
                data: Some(serde_json::json!({
                    "owner_id": owner.id,
                    "email": owner.email,
                    "is_2fa": true,
                })),
            }),
        );
    }

    let token = generate_token(
        &owner.email,
        owner.id,
        "owner",
        owner.id,
        Some(format!("{:?}", owner.paket_langganan).to_lowercase()),
        &state.jwt_secret,
    ).unwrap_or_default();

    (
        StatusCode::OK,
        Json(ApiResponse {
            status: "success".to_string(),
            message: "Login Owner berhasil.".to_string(),
            data: Some(serde_json::to_value(OwnerAuthResponse {
                token,
                owner_id: owner.id,
                nama: owner.nama.clone(),
                email: owner.email.clone(),
                nama_bisnis: owner.nama_bisnis_induk.clone(),
                paket: owner.paket_langganan.clone(),
                kuota_unit_usaha: owner.kuota_unit_usaha,
                sisa_kuota_ai: owner.sisa_kuota_ai,
            }).unwrap()),
        }),
    )
}

// 3. VERIFIKASI 2FA OWNER
pub async fn verify_owner_2fa(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<Verify2FARequest>,
) -> impl IntoResponse {
    let owners = state.owners.read().await;

    // Cari owner berdasarkan email
    let owner = match owners.iter().find(|o| o.email.to_lowercase() == payload.email.to_lowercase()) {
        Some(o) => o,
        None => {
            return (
                StatusCode::NOT_FOUND,
                Json(ApiResponse::<OwnerAuthResponse> {
                    status: "error".to_string(),
                    message: "Akun owner tidak ditemukan.".to_string(),
                    data: None,
                }),
            );
        }
    };

    // Validasi OTP
    if payload.code_otp.trim().len() < 4 {
        return (
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<OwnerAuthResponse> {
                status: "error".to_string(),
                message: "Kode 2FA tidak valid.".to_string(),
                data: None,
            }),
        );
    }

    let token = generate_token(
        &owner.email,
        owner.id,
        "owner",
        owner.id,
        Some(format!("{:?}", owner.paket_langganan).to_lowercase()),
        &state.jwt_secret,
    ).unwrap_or_default();

    (
        StatusCode::OK,
        Json(ApiResponse {
            status: "success".to_string(),
            message: "Verifikasi 2FA berhasil! Selamat datang Owner.".to_string(),
            data: Some(OwnerAuthResponse {
                token,
                owner_id: owner.id,
                nama: owner.nama.clone(),
                email: owner.email.clone(),
                nama_bisnis: owner.nama_bisnis_induk.clone(),
                paket: owner.paket_langganan.clone(),
                kuota_unit_usaha: owner.kuota_unit_usaha,
                sisa_kuota_ai: owner.sisa_kuota_ai,
            }),
        }),
    )
}

// 4. UPGRADE PAKET OWNER (Untuk Tambah Usaha & Fitur AI)
pub async fn upgrade_owner_tier(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<UpgradeTierRequest>,
) -> impl IntoResponse {
    let mut owners = state.owners.write().await;

    if let Some(owner) = owners.first_mut() {
        owner.paket_langganan = payload.paket_baru.clone();

        match payload.paket_baru {
            PaketLangganan::Free => {
                owner.kuota_unit_usaha = 2;
                owner.sisa_kuota_ai = 20;
            }
            PaketLangganan::Pro => {
                owner.kuota_unit_usaha = 5;
                owner.sisa_kuota_ai = 250;
            }
            PaketLangganan::Enterprise => {
                owner.kuota_unit_usaha = 999; // Unlimited unit usaha
                owner.sisa_kuota_ai = 99999;  // Unlimited AI
            }
        }

        (
            StatusCode::OK,
            Json(ApiResponse {
                status: "success".to_string(),
                message: format!("Paket Owner berhasil di-upgrade ke {:?}", payload.paket_baru),
                data: Some(OwnerAuthResponse {
                    token: "".to_string(),
                    owner_id: owner.id,
                    nama: owner.nama.clone(),
                    email: owner.email.clone(),
                    nama_bisnis: owner.nama_bisnis_induk.clone(),
                    paket: owner.paket_langganan.clone(),
                    kuota_unit_usaha: owner.kuota_unit_usaha,
                    sisa_kuota_ai: owner.sisa_kuota_ai,
                }),
            }),
        )
    } else {
        (
            StatusCode::NOT_FOUND,
            Json(ApiResponse {
                status: "error".to_string(),
                message: "Owner tidak ditemukan.".to_string(),
                data: None,
            }),
        )
    }
}

// 5. LOGIN KARYAWAN (Manager, Kasir, Admin Gudang, Auditor)
// Tidak ada register karyawan; karyawan hanya didaftarkan oleh Owner
pub async fn login_karyawan(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<LoginKaryawanRequest>,
) -> impl IntoResponse {
    let karyawans = state.karyawans.read().await;

    let karyawan = match karyawans.iter().find(|k| k.email.to_lowercase() == payload.email.to_lowercase()) {
        Some(k) => k,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(ApiResponse::<KaryawanAuthResponse> {
                    status: "error".to_string(),
                    message: "Email atau kata sandi Karyawan tidak terdaftar.".to_string(),
                    data: None,
                }),
            );
        }
    };

    if !karyawan.is_active {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<KaryawanAuthResponse> {
                status: "error".to_string(),
                message: "Akun karyawan telah dinonaktifkan oleh Owner.".to_string(),
                data: None,
            }),
        );
    }

    if !verify(&payload.password, &karyawan.password_hash).unwrap_or(false) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<KaryawanAuthResponse> {
                status: "error".to_string(),
                message: "Email atau kata sandi Karyawan tidak terdaftar.".to_string(),
                data: None,
            }),
        );
    }

    // Jika karyawan memilih unit, validasi apakah ia memiliki hak akses ke unit tersebut
    if let Some(unit_id) = payload.unit_id_pilihan {
        if !karyawan.unit_akses_ids.is_empty() && !karyawan.unit_akses_ids.contains(&unit_id) {
            return (
                StatusCode::FORBIDDEN,
                Json(ApiResponse::<KaryawanAuthResponse> {
                    status: "error".to_string(),
                    message: "Anda tidak memiliki hak akses ke unit usaha yang dipilih.".to_string(),
                    data: None,
                }),
            );
        }
    }

    let role_str = match karyawan.peran {
        crate::models::PeranPengguna::Manager => "manager",
        crate::models::PeranPengguna::Kasir => "kasir",
        crate::models::PeranPengguna::AdminGudang => "admin_gudang",
        crate::models::PeranPengguna::Auditor => "auditor",
        _ => "karyawan",
    };

    let token = generate_token(
        &karyawan.email,
        karyawan.id,
        role_str,
        karyawan.owner_id,
        None, // Karyawan tidak memiliki paket subscription
        &state.jwt_secret,
    ).unwrap_or_default();

    (
        StatusCode::OK,
        Json(ApiResponse {
            status: "success".to_string(),
            message: format!("Login berhasil sebagai {:?}", karyawan.peran),
            data: Some(KaryawanAuthResponse {
                token,
                karyawan_id: karyawan.id,
                nama: karyawan.nama.clone(),
                email: karyawan.email.clone(),
                peran: karyawan.peran.clone(),
                owner_id: karyawan.owner_id,
                unit_akses_ids: karyawan.unit_akses_ids.clone(),
            }),
        }),
    )
}
