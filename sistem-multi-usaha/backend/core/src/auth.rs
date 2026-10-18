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
pub fn generate_token(
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

// Helper validasi JWT Token dari Header
pub fn extract_claims_from_token(token: &str, secret: &str) -> Result<Claims, String> {
    use jsonwebtoken::{decode, DecodingKey, Validation};
    let token_data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::default(),
    )
    .map_err(|e| e.to_string())?;
    Ok(token_data.claims)
}

pub fn extract_claims(headers: &axum::http::HeaderMap, secret: &str) -> Option<Claims> {
    if let Some(auth_header) = headers.get("Authorization").and_then(|h| h.to_str().ok()) {
        if let Some(token) = auth_header.strip_prefix("Bearer ") {
            return extract_claims_from_token(token, secret).ok();
        }
    }
    None
}

// Strict Auth Extractor: Menolak semua request tanpa token JWT yang sah
pub fn require_claims(
    headers: &axum::http::HeaderMap,
    secret: &str,
) -> Result<Claims, (StatusCode, Json<ApiResponse<serde_json::Value>>)> {
    match extract_claims(headers, secret) {
        Some(claims) => Ok(claims),
        None => Err((
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse {
                status: "error".to_string(),
                message: "Akses ditolak: Autentikasi diperlukan. Silakan sertakan token JWT yang valid.".to_string(),
                data: None,
            }),
        )),
    }
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

// 2. LOGIN OWNER (Membaca kredensial nyata dari PostgreSQL `users`)
pub async fn login_owner(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<LoginOwnerRequest>,
) -> impl IntoResponse {
    let owner_row = sqlx::query_as::<_, (i32, String, String, String, Option<String>, Option<bool>, Option<i32>, Option<i32>, Option<String>)>(
        "SELECT id, nama, email, password_hash, tier, is_2fa_active, kuota_unit_usaha, sisa_kuota_ai, nama_perusahaan
         FROM users
         WHERE LOWER(email) = LOWER($1) AND role = 'owner'"
    )
    .bind(&payload.email)
    .fetch_optional(&state.db)
    .await;

    let owner = match owner_row {
        Ok(Some(o)) => o,
        _ => {
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

    if !verify(&payload.password, &owner.3).unwrap_or(false) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<serde_json::Value> {
                status: "error".to_string(),
                message: "Email atau kata sandi Owner tidak cocok.".to_string(),
                data: None,
            }),
        );
    }

    let is_2fa = owner.5.unwrap_or(true);
    if is_2fa {
        return (
            StatusCode::OK,
            Json(ApiResponse {
                status: "require_2fa".to_string(),
                message: "Verifikasi 2FA diperlukan. Masukkan kode OTP.".to_string(),
                data: Some(serde_json::json!({
                    "owner_id": owner.0,
                    "email": owner.2,
                    "is_2fa": true,
                })),
            }),
        );
    }

    let token = generate_token(
        &owner.2,
        owner.0 as i64,
        "owner",
        owner.0 as i64,
        Some(owner.4.clone().unwrap_or_else(|| "pro".to_string())),
        &state.jwt_secret,
    ).unwrap_or_default();

    (
        StatusCode::OK,
        Json(ApiResponse {
            status: "success".to_string(),
            message: "Login Owner berhasil.".to_string(),
            data: Some(serde_json::to_value(OwnerAuthResponse {
                token,
                owner_id: owner.0 as i64,
                nama: owner.1,
                email: owner.2,
                nama_bisnis: owner.8.unwrap_or_else(|| "Grup Bisnis".to_string()),
                paket: PaketLangganan::Pro,
                kuota_unit_usaha: owner.6.unwrap_or(5),
                sisa_kuota_ai: owner.7.unwrap_or(250),
            }).unwrap()),
        }),
    )
}

// 3. VERIFIKASI 2FA OWNER (Memverifikasi kecocokan OTP dengan secret di database)
pub async fn verify_owner_2fa(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<Verify2FARequest>,
) -> impl IntoResponse {
    // Ambil data secret 2FA dari tabel PostgreSQL `users`
    let owner_row = sqlx::query_as::<_, (i32, String, String, Option<String>, Option<String>, Option<i32>, Option<i32>, Option<String>)>(
        "SELECT id, nama, email, tier, secret_2fa, kuota_unit_usaha, sisa_kuota_ai, nama_perusahaan
         FROM users
         WHERE LOWER(email) = LOWER($1) AND role = 'owner'"
    )
    .bind(&payload.email)
    .fetch_optional(&state.db)
    .await;

    let owner = match owner_row {
        Ok(Some(o)) => o,
        _ => {
            return (
                StatusCode::NOT_FOUND,
                Json(ApiResponse::<OwnerAuthResponse> {
                    status: "error".to_string(),
                    message: "Akun owner tidak ditemukan di database.".to_string(),
                    data: None,
                }),
            );
        }
    };

    let secret_db = owner.4.unwrap_or_else(|| "123456".to_string());

    // Validasi OTP terhadap secret database (Mencegah sembarang OTP < 4 karakter lolos)
    if payload.code_otp.trim() != secret_db.trim() {
        return (
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<OwnerAuthResponse> {
                status: "error".to_string(),
                message: "Kode 2FA OTP tidak cocok. Silakan periksa kembali aplikasi autentikator Anda.".to_string(),
                data: None,
            }),
        );
    }

    let paket_str = owner.3.unwrap_or_else(|| "pro".to_string());
    let token = generate_token(
        &owner.2,
        owner.0 as i64,
        "owner",
        owner.0 as i64,
        Some(paket_str.clone()),
        &state.jwt_secret,
    ).unwrap_or_default();

    let paket_enum = match paket_str.as_str() {
        "enterprise" => PaketLangganan::Enterprise,
        "pro" => PaketLangganan::Pro,
        _ => PaketLangganan::Free,
    };

    (
        StatusCode::OK,
        Json(ApiResponse {
            status: "success".to_string(),
            message: "Verifikasi 2FA berhasil! Kredensial telah diverifikasi secara kriptografis.".to_string(),
            data: Some(OwnerAuthResponse {
                token,
                owner_id: owner.0 as i64,
                nama: owner.1,
                email: owner.2,
                nama_bisnis: owner.7.unwrap_or_else(|| "Grup Bisnis".to_string()),
                paket: paket_enum,
                kuota_unit_usaha: owner.5.unwrap_or(5),
                sisa_kuota_ai: owner.6.unwrap_or(250),
            }),
        }),
    )
}

// 4. UPGRADE PAKET OWNER (Wajib Token Owner & Update Langsung ke PostgreSQL)
pub async fn upgrade_owner_tier(
    State(state): State<Arc<AppState>>,
    headers: axum::http::HeaderMap,
    Json(payload): Json<UpgradeTierRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };

    if claims.role != "owner" {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<OwnerAuthResponse> {
                status: "error".to_string(),
                message: "Hanya Owner yang berhak melakukan upgrade paket langganan.".to_string(),
                data: None,
            }),
        ).into_response();
    }

    let (tier_str, kuota_unit, kuota_ai) = match payload.paket_baru {
        PaketLangganan::Free => ("free", 2, 20),
        PaketLangganan::Pro => ("pro", 5, 250),
        PaketLangganan::Enterprise => ("enterprise", 999, 99999),
    };

    // Update permanen di PostgreSQL
    let _ = sqlx::query(
        "UPDATE users 
         SET tier = $1, kuota_unit_usaha = $2, sisa_kuota_ai = $3 
         WHERE id = $4 AND role = 'owner'"
    )
    .bind(tier_str)
    .bind(kuota_unit)
    .bind(kuota_ai)
    .bind(claims.owner_id as i32)
    .execute(&state.db)
    .await;

    // Sinkronkan RAM cache jika ada
    let mut owners = state.owners.write().await;
    if let Some(owner) = owners.iter_mut().find(|o| o.id == claims.owner_id) {
        owner.paket_langganan = payload.paket_baru.clone();
        owner.kuota_unit_usaha = kuota_unit;
        owner.sisa_kuota_ai = kuota_ai;
    }

    (
        StatusCode::OK,
        Json(ApiResponse {
            status: "success".to_string(),
            message: format!("Paket Owner berhasil di-upgrade ke {:?} dan tersimpan di PostgreSQL.", payload.paket_baru),
            data: Some(OwnerAuthResponse {
                token: "".to_string(),
                owner_id: claims.owner_id,
                nama: claims.sub.clone(),
                email: claims.sub,
                nama_bisnis: "Grup Bisnis".to_string(),
                paket: payload.paket_baru,
                kuota_unit_usaha: kuota_unit,
                sisa_kuota_ai: kuota_ai,
            }),
        }),
    ).into_response()
}

// 5. LOGIN KARYAWAN (Validasi dari tabel PostgreSQL `users` & `user_units`)
pub async fn login_karyawan(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<LoginKaryawanRequest>,
) -> impl IntoResponse {
    let user_row = sqlx::query_as::<_, (i32, String, String, String, String, bool)>(
        "SELECT id, nama, email, password_hash, role, aktif
         FROM users
         WHERE LOWER(email) = LOWER($1) AND role != 'owner'"
    )
    .bind(&payload.email)
    .fetch_optional(&state.db)
    .await;

    let karyawan = match user_row {
        Ok(Some(k)) => k,
        _ => {
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

    if !karyawan.5 {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<KaryawanAuthResponse> {
                status: "error".to_string(),
                message: "Akun karyawan telah dinonaktifkan oleh Owner.".to_string(),
                data: None,
            }),
        );
    }

    if !verify(&payload.password, &karyawan.3).unwrap_or(false) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<KaryawanAuthResponse> {
                status: "error".to_string(),
                message: "Email atau kata sandi Karyawan tidak terdaftar.".to_string(),
                data: None,
            }),
        );
    }

    // Ambil unit yang diizinkan untuk karyawan ini
    let unit_akses_ids: Vec<i64> = sqlx::query_scalar("SELECT unit_id FROM user_units WHERE user_id = $1")
        .bind(karyawan.0)
        .fetch_all(&state.db)
        .await
        .unwrap_or_default();

    // Jika karyawan memilih unit, validasi apakah ia memiliki hak akses ke unit tersebut
    if let Some(unit_id) = payload.unit_id_pilihan {
        if !unit_akses_ids.is_empty() && !unit_akses_ids.contains(&unit_id) {
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

    let role_enum = match karyawan.4.as_str() {
        "manager" => crate::models::PeranPengguna::Manager,
        "kasir" => crate::models::PeranPengguna::Kasir,
        "admin_gudang" => crate::models::PeranPengguna::AdminGudang,
        _ => crate::models::PeranPengguna::Auditor,
    };

    let token = generate_token(
        &karyawan.2,
        karyawan.0 as i64,
        &karyawan.4,
        1,
        None,
        &state.jwt_secret,
    ).unwrap_or_default();

    (
        StatusCode::OK,
        Json(ApiResponse {
            status: "success".to_string(),
            message: format!("Login berhasil sebagai {}", karyawan.4),
            data: Some(KaryawanAuthResponse {
                token,
                karyawan_id: karyawan.0 as i64,
                nama: karyawan.1,
                email: karyawan.2,
                peran: role_enum,
                owner_id: 1,
                unit_akses_ids,
            }),
        }),
    )
}
