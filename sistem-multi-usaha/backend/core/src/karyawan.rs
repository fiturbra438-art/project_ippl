use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use bcrypt::hash;
use std::sync::Arc;

use crate::auth::require_claims;
use crate::models::{AuditLogModel, KaryawanAccount, PeranPengguna};
use crate::schemas::{ApiResponse, CreateKaryawanRequest, UpdateKaryawanRequest};
use crate::state::AppState;

// 1. LIST KARYAWAN (Dari tabel PostgreSQL `users`)
pub async fn list_karyawan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let _claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };

    let rows = sqlx::query_as::<_, (i32, String, String, String, String, bool)>(
        "SELECT id, nama, email, password_hash, role, aktif
         FROM users
         WHERE role != 'owner'
         ORDER BY id ASC"
    )
    .fetch_all(&state.db)
    .await;

    let mut hasil: Vec<KaryawanAccount> = Vec::new();
    if let Ok(users) = rows {
        for u in users {
            let unit_ids: Vec<i64> = sqlx::query_scalar("SELECT unit_id FROM user_units WHERE user_id = $1")
                .bind(u.0)
                .fetch_all(&state.db)
                .await
                .unwrap_or_default();

            hasil.push(KaryawanAccount {
                id: u.0 as i64,
                owner_id: 1,
                nama: u.1,
                email: u.2,
                password_hash: u.3,
                peran: match u.4.as_str() {
                    "manager" => PeranPengguna::Manager,
                    "kasir" => PeranPengguna::Kasir,
                    "admin_gudang" => PeranPengguna::AdminGudang,
                    _ => PeranPengguna::Auditor,
                },
                unit_akses_ids: unit_ids,
                is_active: u.5,
            });
        }
    }

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<KaryawanAccount>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} akun karyawan dari database.", hasil.len()),
            data: Some(hasil),
        }),
    ).into_response()
}

// 2. TAMBAH KARYAWAN (Tersimpan Permanen ke PostgreSQL `users` & `user_units`)
pub async fn create_karyawan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateKaryawanRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;
    let aktor_nama = claims.sub.clone();

    let password_hash = hash(&payload.password, 4).unwrap_or_default();
    let role_str = match payload.peran {
        PeranPengguna::Manager => "manager",
        PeranPengguna::Kasir => "kasir",
        PeranPengguna::AdminGudang => "admin_gudang",
        PeranPengguna::Auditor => "auditor",
        _ => "karyawan",
    };

    let user_row: Result<(i32,), sqlx::Error> = sqlx::query_as(
        "INSERT INTO users (nama, email, password_hash, role, aktif, created_at)
         VALUES ($1, $2, $3, $4, true, now())
         RETURNING id"
    )
    .bind(&payload.nama)
    .bind(&payload.email)
    .bind(&password_hash)
    .bind(role_str)
    .fetch_one(&state.db)
    .await;

    let user_id = match user_row {
        Ok(r) => r.0,
        Err(e) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<KaryawanAccount> {
                    status: "error".to_string(),
                    message: format!("Gagal mendaftarkan karyawan (kemungkinan email duplikat): {}", e),
                    data: None,
                }),
            ).into_response();
        }
    };

    // Hubungkan karyawan ke unit usaha di tabel `user_units`
    for uid in &payload.unit_akses_ids {
        let _ = sqlx::query("INSERT INTO user_units (user_id, unit_id) VALUES ($1, $2)")
            .bind(user_id)
            .bind(*uid as i32)
            .execute(&state.db)
            .await;
    }

    // Catat Audit Trail
    let _ = sqlx::query(
        "INSERT INTO audit_logs (owner_id, aktor, role, aksi, modul, target, detail, waktu)
         VALUES ($1, $2, 'owner', 'Daftarkan Karyawan', 'Pengguna', $3, $4, now())"
    )
    .bind(owner_id as i32)
    .bind(&aktor_nama)
    .bind(&payload.nama)
    .bind(format!("Membuat akun karyawan {} sebagai {}", payload.email, role_str))
    .execute(&state.db)
    .await;

    let new_karyawan = KaryawanAccount {
        id: user_id as i64,
        owner_id,
        nama: payload.nama,
        email: payload.email,
        password_hash,
        peran: payload.peran,
        unit_akses_ids: payload.unit_akses_ids,
        is_active: true,
    };

    (
        StatusCode::CREATED,
        Json(ApiResponse::<KaryawanAccount> {
            status: "success".to_string(),
            message: "Karyawan baru berhasil didaftarkan dan tersimpan permanen di database PostgreSQL.".to_string(),
            data: Some(new_karyawan),
        }),
    ).into_response()
}

// 3. UPDATE KARYAWAN
pub async fn update_karyawan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateKaryawanRequest>,
) -> impl IntoResponse {
    let _claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };

    if let Some(nama) = &payload.nama {
        let _ = sqlx::query("UPDATE users SET nama = $1 WHERE id = $2").bind(nama).bind(id as i32).execute(&state.db).await;
    }
    if let Some(peran) = &payload.peran {
        let role_str = match peran {
            PeranPengguna::Manager => "manager",
            PeranPengguna::Kasir => "kasir",
            PeranPengguna::AdminGudang => "admin_gudang",
            _ => "auditor",
        };
        let _ = sqlx::query("UPDATE users SET role = $1 WHERE id = $2").bind(role_str).bind(id as i32).execute(&state.db).await;
    }
    if let Some(active) = payload.is_active {
        let _ = sqlx::query("UPDATE users SET aktif = $1 WHERE id = $2").bind(active).bind(id as i32).execute(&state.db).await;
    }
    if let Some(unit_ids) = &payload.unit_akses_ids {
        let _ = sqlx::query("DELETE FROM user_units WHERE user_id = $1").bind(id as i32).execute(&state.db).await;
        for uid in unit_ids {
            let _ = sqlx::query("INSERT INTO user_units (user_id, unit_id) VALUES ($1, $2)").bind(id as i32).bind(*uid as i32).execute(&state.db).await;
        }
    }

    (
        StatusCode::OK,
        Json(ApiResponse::<()> {
            status: "success".to_string(),
            message: format!("Akses dan posisi karyawan #{} berhasil diperbarui di PostgreSQL.", id),
            data: None,
        }),
    ).into_response()
}

// 4. HAPUS KARYAWAN
pub async fn delete_karyawan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let _claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };

    let _ = sqlx::query("DELETE FROM user_units WHERE user_id = $1").bind(id as i32).execute(&state.db).await;
    let res = sqlx::query("DELETE FROM users WHERE id = $1 AND role != 'owner'").bind(id as i32).execute(&state.db).await;

    match res {
        Ok(_) => (
            StatusCode::OK,
            Json(ApiResponse::<()> {
                status: "success".to_string(),
                message: format!("Akun karyawan #{} berhasil dihapus dari database.", id),
                data: None,
            }),
        ).into_response(),
        Err(e) => (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: format!("Gagal menghapus karyawan: {}", e),
                data: None,
            }),
        ).into_response(),
    }
}

// 5. LIST AUDIT TRAIL / LOG AKTIVITAS (Dari tabel PostgreSQL `audit_logs`)
pub async fn list_audit_logs(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;

    let rows = sqlx::query_as::<_, (i32, i32, String, String, String, String, String, String, chrono::NaiveDateTime)>(
        "SELECT id, owner_id, aktor, role, aksi, modul, target, detail, waktu
         FROM audit_logs
         WHERE owner_id = $1
         ORDER BY id DESC
         LIMIT 100"
    )
    .bind(owner_id as i32)
    .fetch_all(&state.db)
    .await;

    let hasil: Vec<AuditLogModel> = match rows {
        Ok(list) => list
            .into_iter()
            .map(|r| AuditLogModel {
                id: r.0 as i64,
                owner_id: r.1 as i64,
                aktor: r.2,
                role: r.3,
                aksi: r.4,
                modul: r.5,
                target: r.6,
                detail: r.7,
                waktu: r.8.format("%Y-%m-%d %H:%M").to_string(),
            })
            .collect(),
        Err(_) => Vec::new(),
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<AuditLogModel>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} catatan audit log dari PostgreSQL.", hasil.len()),
            data: Some(hasil),
        }),
    ).into_response()
}
