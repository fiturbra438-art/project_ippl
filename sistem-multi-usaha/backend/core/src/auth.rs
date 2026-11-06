use axum::{
    async_trait,
    extract::{FromRequestParts, State},
    http::{request::Parts, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use bcrypt::{hash, verify};
use chrono::{Duration, Utc};
use jsonwebtoken::{encode, EncodingKey, Header};
use std::sync::Arc;

use crate::models::{Claims, PaketLangganan};
use crate::schemas::{
    ApiResponse, KaryawanAuthResponse, LoginKaryawanRequest, LoginOwnerRequest, OwnerAuthResponse,
    RegisterOwnerRequest, UpgradeTierRequest, Verify2FARequest,
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

// Perbandingan waktu-konstan untuk mencegah timing attack pada kode OTP.
fn constant_time_eq(a: &str, b: &str) -> bool {
    let a = a.as_bytes();
    let b = b.as_bytes();
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
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
                message:
                    "Akses ditolak: Autentikasi diperlukan. Silakan sertakan token JWT yang valid."
                        .to_string(),
                data: None,
            }),
        )),
    }
}

#[async_trait]
impl FromRequestParts<Arc<AppState>> for Claims {
    type Rejection = Response;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &Arc<AppState>,
    ) -> Result<Self, Self::Rejection> {
        require_claims(&parts.headers, &state.jwt_secret).map_err(|err| err.into_response())
    }
}

/// Otorisasi terpusat untuk endpoint administratif.
pub fn ensure_roles(claims: &Claims, allowed: &[&str]) -> Result<(), Response> {
    if allowed.iter().any(|role| *role == claims.role) {
        Ok(())
    } else {
        Err((
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<serde_json::Value> {
                status: "error".to_string(),
                message: "Anda tidak memiliki hak untuk melakukan tindakan ini.".to_string(),
                data: None,
            }),
        )
            .into_response())
    }
}

/// Otorisasi terpusat berbasis header (kompatibilitas).
#[allow(dead_code)]
pub fn require_roles(
    headers: &axum::http::HeaderMap,
    secret: &str,
    allowed: &[&str],
) -> Result<Claims, axum::response::Response> {
    let claims = require_claims(headers, secret).map_err(|err| err.into_response())?;
    ensure_roles(&claims, allowed)?;
    Ok(claims)
}

// 1. REGISTER OWNER (Hanya Owner yang bisa register mandiri)
pub async fn register_owner(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<RegisterOwnerRequest>,
) -> impl IntoResponse {
    if payload.password.len() < 10 {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<serde_json::Value> {
                status: "error".to_string(),
                message: "Kata sandi minimal 10 karakter.".to_string(),
                data: None,
            }),
        );
    }

    let password_hash = match hash(&payload.password, 12) {
        Ok(h) => h,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    status: "error".to_string(),
                    message: "Gagal mengenkripsi kata sandi.".to_string(),
                    data: None,
                }),
            );
        }
    };

    // Buat 6 digit kode OTP dinamis untuk verifikasi email saat pendaftaran
    let otp_code = crate::email::generate_dynamic_otp();
    let expires_at = Utc::now() + Duration::minutes(5);

    let new_owner_row: Result<(i32,), sqlx::Error> = sqlx::query_as(
        "INSERT INTO users (nama, email, password_hash, role, aktif, nama_perusahaan, tier, kuota_unit_usaha, sisa_kuota_ai, is_2fa_active, otp_code, otp_expires_at)
         VALUES ($1, LOWER($2), $3, 'owner', true, $4, 'free', 2, 20, true, $5, $6)
         RETURNING id"
    )
    .bind(&payload.nama)
    .bind(&payload.email)
    .bind(&password_hash)
    .bind(&payload.nama_bisnis_induk)
    .bind(&otp_code)
    .bind(expires_at.naive_utc())
    .fetch_one(&state.db)
    .await;

    let new_id = match new_owner_row {
        Ok((id,)) => id as i64,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<serde_json::Value> {
                    status: "error".to_string(),
                    message: "Email sudah terdaftar atau registrasi gagal.".to_string(),
                    data: None,
                }),
            )
        }
    };

    // Kirim kode OTP pendaftaran langsung ke email
    let email_owner = payload.email.clone();
    let nama_owner = payload.nama.clone();
    tokio::spawn(async move {
        if let Err(e) = crate::email::send_otp_email(&email_owner, &nama_owner, &otp_code).await {
            tracing::error!("❌ Gagal mengirimkan email OTP registrasi ke {}: {}", email_owner, e);
        }
    });

    (
        StatusCode::CREATED,
        Json(ApiResponse {
            status: "require_2fa".to_string(),
            message: "Registrasi akun berhasil! Kode OTP verifikasi telah dikirimkan ke email Anda.".to_string(),
            data: Some(serde_json::json!({
                "owner_id": new_id,
                "email": payload.email,
                "is_2fa": true,
            })),
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
        // Buat 6 angka OTP acak dinamis
        let otp_code = crate::email::generate_dynamic_otp();
        let expires_at = Utc::now() + Duration::minutes(5);

        // Simpan OTP, reset penghitung percobaan, dan masa kedaluwarsa
        if let Err(e) = sqlx::query(
            "UPDATE users
             SET otp_code = $1, otp_expires_at = $2, otp_attempts = 0
             WHERE id = $3",
        )
        .bind(&otp_code)
        .bind(expires_at.naive_utc())
        .bind(owner.0)
        .execute(&state.db)
        .await
        {
            tracing::error!("Gagal menyimpan OTP untuk owner #{}: {}", owner.0, e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    status: "error".to_string(),
                    message: "Gagal membuat kode OTP. Silakan coba lagi.".to_string(),
                    data: None,
                }),
            );
        }

        // Kirimkan OTP ke email Owner secara asynchronous
        let email_owner = owner.2.clone();
        let nama_owner = owner.1.clone();
        tokio::spawn(async move {
            if let Err(e) = crate::email::send_otp_email(&email_owner, &nama_owner, &otp_code).await {
                tracing::error!("❌ Gagal mengirimkan email OTP ke {}: {}", email_owner, e);
            }
        });

        return (
            StatusCode::OK,
            Json(ApiResponse {
                status: "require_2fa".to_string(),
                message: "Verifikasi 2FA diperlukan. Kode OTP telah dikirimkan ke email Anda dan berlaku 5 menit.".to_string(),
                data: Some(serde_json::json!({
                    "owner_id": owner.0,
                    "email": owner.2,
                    "is_2fa": true,
                })),
            }),
        );
    }

    let paket_str = owner.4.clone().unwrap_or_else(|| "free".to_string());
    let paket_enum = match paket_str.as_str() {
        "enterprise" => PaketLangganan::Enterprise,
        "pro" => PaketLangganan::Pro,
        _ => PaketLangganan::Free,
    };

    let token = match generate_token(
        &owner.2,
        owner.0 as i64,
        "owner",
        owner.0 as i64,
        Some(paket_str),
        &state.jwt_secret,
    ) {
        Ok(t) => t,
        Err(e) => {
            tracing::error!("Gagal membuat token login owner: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    status: "error".to_string(),
                    message: "Gagal membuat sesi login. Silakan coba lagi.".to_string(),
                    data: None,
                }),
            );
        }
    };

    (
        StatusCode::OK,
        Json(ApiResponse {
            status: "success".to_string(),
            message: "Login Owner berhasil.".to_string(),
            data: match serde_json::to_value(OwnerAuthResponse {
                token,
                owner_id: owner.0 as i64,
                nama: owner.1,
                email: owner.2,
                nama_bisnis: owner.8.unwrap_or_else(|| "Grup Bisnis".to_string()),
                paket: paket_enum,
                kuota_unit_usaha: owner.6.unwrap_or(5),
                sisa_kuota_ai: owner.7.unwrap_or(250),
            }) {
                Ok(val) => Some(val),
                Err(e) => {
                    tracing::error!("Gagal serialisasi OwnerAuthResponse: {}", e);
                    None
                }
            },
        }),
    )
}

// 3. VERIFIKASI 2FA OWNER (Memverifikasi kecocokan OTP dengan secret di database)
pub async fn verify_owner_2fa(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<Verify2FARequest>,
) -> impl IntoResponse {
    // Ambil data secret 2FA dari tabel PostgreSQL `users`
    let owner_row = sqlx::query_as::<
        _,
        (
            i32,
            String,
            String,
            String,
            Option<String>,
            Option<String>,
            Option<i32>,
            Option<i32>,
            Option<String>,
        ),
    >(
        "SELECT id, nama, email, password_hash, tier, secret_2fa, kuota_unit_usaha, sisa_kuota_ai, nama_perusahaan
         FROM users
         WHERE LOWER(email) = LOWER($1) AND role = 'owner'",
    )
    .bind(&payload.email)
    .fetch_optional(&state.db)
    .await;

    let owner = match owner_row {
        Ok(Some(o)) => o,
        _ => {
            // Jangan bocorkan keberadaan akun (anti-enumeration)
            return (
                StatusCode::UNAUTHORIZED,
                Json(ApiResponse::<OwnerAuthResponse> {
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
            Json(ApiResponse::<OwnerAuthResponse> {
                status: "error".to_string(),
                message: "Email atau kata sandi Owner tidak cocok.".to_string(),
                data: None,
            }),
        );
    }

    // Ambil data OTP dinamis, masa kedaluwarsa, dan jumlah percobaan dari PostgreSQL
    let otp_row = sqlx::query_as::<_, (Option<String>, Option<chrono::NaiveDateTime>, Option<i32>)>(
        "SELECT otp_code, otp_expires_at, otp_attempts FROM users WHERE id = $1",
    )
    .bind(owner.0)
    .fetch_optional(&state.db)
    .await
    .unwrap_or(None);

    // Tidak ada fallback ke secret statis: OTP harus berasal dari login terbaru.
    let (db_otp, db_expires, attempts) = match otp_row {
        Some((Some(code), Some(exp), attempts)) => (code, exp, attempts.unwrap_or(0)),
        _ => {
            return (
                StatusCode::FORBIDDEN,
                Json(ApiResponse::<OwnerAuthResponse> {
                    status: "error".to_string(),
                    message: "Tidak ada kode OTP aktif. Silakan login ulang untuk mendapatkan kode OTP baru.".to_string(),
                    data: None,
                }),
            );
        }
    };

    const MAX_OTP_ATTEMPTS: i32 = 5;
    if attempts >= MAX_OTP_ATTEMPTS {
        let _ = sqlx::query(
            "UPDATE users SET otp_code = NULL, otp_expires_at = NULL WHERE id = $1",
        )
        .bind(owner.0)
        .execute(&state.db)
        .await;
        return (
            StatusCode::TOO_MANY_REQUESTS,
            Json(ApiResponse::<OwnerAuthResponse> {
                status: "error".to_string(),
                message: "Terlalu banyak percobaan kode OTP. Silakan login ulang untuk meminta kode baru.".to_string(),
                data: None,
            }),
        );
    }

    // Validasi kedaluwarsa OTP (5 menit)
    if Utc::now().naive_utc() > db_expires {
        return (
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<OwnerAuthResponse> {
                status: "error".to_string(),
                message: "Kode OTP telah kedaluwarsa. Silakan login ulang untuk meminta kode OTP baru.".to_string(),
                data: None,
            }),
        );
    }

    // Validasi kecocokan kode OTP dengan perbandingan waktu-konstan
    if !constant_time_eq(payload.code_otp.trim(), db_otp.trim()) {
        let new_attempts = attempts + 1;
        if new_attempts >= MAX_OTP_ATTEMPTS {
            // Kunci OTP setelah batas percobaan tercapai
            let _ = sqlx::query(
                "UPDATE users SET otp_code = NULL, otp_expires_at = NULL, otp_attempts = $1 WHERE id = $2",
            )
            .bind(new_attempts)
            .bind(owner.0)
            .execute(&state.db)
            .await;
            return (
                StatusCode::TOO_MANY_REQUESTS,
                Json(ApiResponse::<OwnerAuthResponse> {
                    status: "error".to_string(),
                    message: "Terlalu banyak percobaan kode OTP. Silakan login ulang untuk meminta kode baru.".to_string(),
                    data: None,
                }),
            );
        }

        let _ = sqlx::query("UPDATE users SET otp_attempts = $1 WHERE id = $2")
            .bind(new_attempts)
            .bind(owner.0)
            .execute(&state.db)
            .await;

        return (
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<OwnerAuthResponse> {
                status: "error".to_string(),
                message: format!(
                    "Kode OTP tidak cocok. Sisa percobaan: {}.",
                    MAX_OTP_ATTEMPTS - new_attempts
                ),
                data: None,
            }),
        );
    }

    // Hanguskan OTP setelah berhasil dipakai (mencegah replay attack)
    let _ = sqlx::query(
        "UPDATE users SET otp_code = NULL, otp_expires_at = NULL, otp_attempts = 0 WHERE id = $1",
    )
    .bind(owner.0)
    .execute(&state.db)
    .await;

    let paket_str = owner.4.clone().unwrap_or_else(|| "free".to_string());
    let token = match generate_token(
        &owner.2,
        owner.0 as i64,
        "owner",
        owner.0 as i64,
        Some(paket_str.clone()),
        &state.jwt_secret,
    ) {
        Ok(t) => t,
        Err(e) => {
            tracing::error!("Gagal membuat token 2FA owner: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<OwnerAuthResponse> {
                    status: "error".to_string(),
                    message: "Gagal membuat sesi login. Silakan coba lagi.".to_string(),
                    data: None,
                }),
            );
        }
    };

    let paket_enum = match paket_str.as_str() {
        "enterprise" => PaketLangganan::Enterprise,
        "pro" => PaketLangganan::Pro,
        _ => PaketLangganan::Free,
    };

    (
        StatusCode::OK,
        Json(ApiResponse {
            status: "success".to_string(),
            message: "Verifikasi 2FA berhasil! Kredensial telah diverifikasi secara kriptografis."
                .to_string(),
            data: Some(OwnerAuthResponse {
                token,
                owner_id: owner.0 as i64,
                nama: owner.1,
                email: owner.2,
                nama_bisnis: owner.8.unwrap_or_else(|| "Grup Bisnis".to_string()),
                paket: paket_enum,
                kuota_unit_usaha: owner.6.unwrap_or(5),
                sisa_kuota_ai: owner.7.unwrap_or(250),
            }),
        }),
    )
}

// 4. UPGRADE PAKET OWNER (Wajib Token Owner & Update Langsung ke PostgreSQL)
pub async fn upgrade_owner_tier(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Json(payload): Json<UpgradeTierRequest>,
) -> impl IntoResponse {
    if claims.role != "owner" {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<OwnerAuthResponse> {
                status: "error".to_string(),
                message: "Hanya Owner yang berhak melakukan upgrade paket langganan.".to_string(),
                data: None,
            }),
        )
            .into_response();
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
         WHERE id = $4 AND role = 'owner'",
    )
    .bind(tier_str)
    .bind(kuota_unit)
    .bind(kuota_ai)
    .bind(claims.owner_id as i32)
    .execute(&state.db)
    .await;

    (
        StatusCode::OK,
        Json(ApiResponse {
            status: "success".to_string(),
            message: format!(
                "Paket Owner berhasil di-upgrade ke {:?} dan tersimpan di PostgreSQL.",
                payload.paket_baru
            ),
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
    )
        .into_response()
}

// 5. LOGIN KARYAWAN (Validasi dari tabel PostgreSQL `users` & `user_units`)
pub async fn login_karyawan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<LoginKaryawanRequest>,
) -> impl IntoResponse {
    let client_platform = headers
        .get("x-client-platform")
        .and_then(|h| h.to_str().ok())
        .unwrap_or("app");

    let user_row = sqlx::query_as::<_, (i32, Option<i32>, String, String, String, String, bool)>(
        "SELECT id, owner_id, nama, email, password_hash, role, aktif
         FROM users
         WHERE LOWER(email) = LOWER($1) AND role != 'owner'",
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

    // Platform guard: Web hanya untuk Owner, Manager, dan Admin Gudang
    if client_platform == "web" && karyawan.5 != "manager" && karyawan.5 != "admin_gudang" {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<KaryawanAuthResponse> {
                status: "error".to_string(),
                message: "Portal Web dikhususkan untuk Manajemen (Owner, Manajer, Admin Gudang). Staf Kasir silakan login melalui Aplikasi Desktop atau POS.".to_string(),
                data: None,
            }),
        );
    }

    if !karyawan.6 {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<KaryawanAuthResponse> {
                status: "error".to_string(),
                message: "Akun karyawan telah dinonaktifkan oleh Owner.".to_string(),
                data: None,
            }),
        );
    }

    if !verify(&payload.password, &karyawan.4).unwrap_or(false) {
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
    let unit_akses_ids: Vec<i64> =
        sqlx::query_scalar("SELECT unit_id FROM user_units WHERE user_id = $1")
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
                    message: "Anda tidak memiliki hak akses ke unit usaha yang dipilih."
                        .to_string(),
                    data: None,
                }),
            );
        }
    }

    let role_enum = match karyawan.5.as_str() {
        "manager" => crate::models::PeranPengguna::Manager,
        "kasir" => crate::models::PeranPengguna::Kasir,
        "admin_gudang" => crate::models::PeranPengguna::AdminGudang,
        _ => crate::models::PeranPengguna::Auditor,
    };

    let target_owner_id = match karyawan.1 {
        Some(oid) => oid as i64,
        None => {
            return (
                StatusCode::FORBIDDEN,
                Json(ApiResponse::<KaryawanAuthResponse> {
                    status: "error".to_string(),
                    message: "Akun karyawan ini tidak terasosiasi dengan pemilik bisnis (owner)."
                        .to_string(),
                    data: None,
                }),
            );
        }
    };

    let token = match generate_token(
        &karyawan.3,
        karyawan.0 as i64,
        &karyawan.5,
        target_owner_id,
        None,
        &state.jwt_secret,
    ) {
        Ok(t) => t,
        Err(e) => {
            tracing::error!("Gagal membuat token login karyawan: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<KaryawanAuthResponse> {
                    status: "error".to_string(),
                    message: "Gagal membuat sesi login. Silakan coba lagi.".to_string(),
                    data: None,
                }),
            );
        }
    };

    (
        StatusCode::OK,
        Json(ApiResponse {
            status: "success".to_string(),
            message: format!("Login berhasil sebagai {}", karyawan.5),
            data: Some(KaryawanAuthResponse {
                token,
                karyawan_id: karyawan.0 as i64,
                nama: karyawan.2,
                email: karyawan.3,
                peran: role_enum,
                owner_id: target_owner_id,
                unit_akses_ids,
            }),
        }),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::{HeaderMap, HeaderValue};

    #[test]
    fn test_generate_and_extract_jwt_claims() {
        let secret = "test_secret_key_for_unit_testing_1234567890";
        let token = generate_token(
            "owner@example.com",
            10,
            "owner",
            10,
            Some("pro".to_string()),
            secret,
        )
        .expect("token harus berhasil dibuat");

        let mut headers = HeaderMap::new();
        headers.insert(
            "Authorization",
            HeaderValue::from_str(&format!("Bearer {}", token)).unwrap(),
        );

        let claims = require_claims(&headers, secret).expect("claims harus valid");
        assert_eq!(claims.sub, "owner@example.com");
        assert_eq!(claims.user_id, 10);
        assert_eq!(claims.role, "owner");
        assert_eq!(claims.owner_id, 10);
        assert_eq!(claims.tier.as_deref(), Some("pro"));
        assert!(ensure_roles(&claims, &["owner", "manager"]).is_ok());
        assert!(ensure_roles(&claims, &["kasir"]).is_err());
    }

    #[test]
    fn test_require_claims_rejects_missing_or_invalid_token() {
        let secret = "test_secret_key_for_unit_testing_1234567890";
        let headers = HeaderMap::new();
        assert!(require_claims(&headers, secret).is_err());
    }
}
