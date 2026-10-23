use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use std::sync::Arc;
use chrono::Local;

use crate::auth::require_claims;
use crate::models::{AuditLogModel, UsahaModel};
use crate::schemas::{ApiResponse, CreateUsahaRequest, UpdateUsahaRequest};
use crate::state::AppState;

// 1. LIST UNIT USAHA (Strict Authentication via PostgreSQL)
pub async fn list_usaha(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;
    let role = claims.role.as_str();

    let usahas = state.usahas.read().await;

    // Filter berdasarkan owner
    let mut hasil: Vec<UsahaModel> = usahas
        .iter()
        .filter(|u| u.owner_id == owner_id)
        .cloned()
        .collect();

    // Jika karyawan dengan hak akses terbatas, filter unit_id
    if role != "owner" && role != "auditor" {
        let karyawans = state.karyawans.read().await;
        if let Some(k) = karyawans.iter().find(|k| k.id == claims.user_id) {
            if !k.unit_akses_ids.is_empty() {
                hasil.retain(|u| k.unit_akses_ids.contains(&u.id));
            }
        }
    }

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<UsahaModel>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} unit usaha.", hasil.len()),
            data: Some(hasil),
        }),
    ).into_response()
}

// 2. DETAIL UNIT USAHA (Dilindungi Validasi Kepemilikan)
pub async fn get_usaha_detail(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let claims = match crate::auth::require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };

    let row = sqlx::query_as::<_, (i32, i32, String, String, Option<String>, Option<String>, bool, Option<bool>)>(
        "SELECT id, owner_id, nama, jenis_usaha, lokasi, kategori_portofolio, status, has_pos 
         FROM business_units 
         WHERE id = $1 AND owner_id = $2"
    )
    .bind(id as i32)
    .bind(claims.owner_id as i32)
    .fetch_optional(&state.db)
    .await;

    match row {
        Ok(Some(u)) => (
            StatusCode::OK,
            Json(ApiResponse::<UsahaModel> {
                status: "success".to_string(),
                message: "Detail unit usaha ditemukan.".to_string(),
                data: Some(UsahaModel {
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
                }),
            }),
        ).into_response(),
        _ => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<UsahaModel> {
                status: "error".to_string(),
                message: "Unit usaha tidak ditemukan atau Anda tidak memiliki hak akses.".to_string(),
                data: None,
            }),
        ).into_response(),
    }
}

// 3. TAMBAH UNIT USAHA (Cek Kuota Tier Langganan)
pub async fn create_usaha(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateUsahaRequest>,
) -> impl IntoResponse {
    let claims = match crate::auth::require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;
    let aktor_nama = claims.sub.clone();
    let aktor_role = claims.role.clone();

    // Cek kuota tier owner
    let owners = state.owners.read().await;
    let owner = match owners.iter().find(|o| o.id == owner_id) {
        Some(o) => o.clone(),
        None => {
            return (
                StatusCode::FORBIDDEN,
                Json(ApiResponse::<UsahaModel> {
                    status: "error".to_string(),
                    message: "Akun owner tidak valid.".to_string(),
                    data: None,
                }),
            ).into_response();
        }
    };
    drop(owners);

    let mut usahas = state.usahas.write().await;
    let current_count = usahas.iter().filter(|u| u.owner_id == owner_id).count();

    if current_count >= (owner.kuota_unit_usaha as usize) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<UsahaModel> {
                status: "error".to_string(),
                message: format!(
                    "Batas kuota paket ({:?}) telah tercapai (Maksimal {} unit usaha). Silakan upgrade paket ke Pro atau Enterprise untuk menambah cabang baru.",
                    owner.paket_langganan, owner.kuota_unit_usaha
                ),
                data: None,
            }),
        ).into_response();
    }

    // Simpan permanen ke PostgreSQL
    let row_id: Result<(i32,), sqlx::Error> = sqlx::query_as(
        "INSERT INTO business_units (owner_id, nama, jenis_usaha, lokasi, kategori_portofolio, status, has_pos)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id"
    )
    .bind(owner_id as i32)
    .bind(&payload.nama)
    .bind(&payload.jenis_usaha)
    .bind(&payload.lokasi)
    .bind(payload.kategori_portofolio.as_deref().unwrap_or("Star"))
    .bind(true)
    .bind(payload.has_pos.unwrap_or(true))
    .fetch_one(&state.db)
    .await;

    let new_id = match row_id {
        Ok(r) => r.0 as i64,
        Err(_) => (usahas.len() as i64) + 1,
    };

    let new_usaha = UsahaModel {
        id: new_id,
        owner_id,
        nama: payload.nama.clone(),
        jenis_usaha: payload.jenis_usaha,
        lokasi: payload.lokasi,
        kategori_portofolio: payload.kategori_portofolio.unwrap_or_else(|| "Star".to_string()),
        pendapatan_bulan_ini: 0.0,
        pengeluaran_bulan_ini: 0.0,
        pertumbuhan_persen: 0.0,
        status: true,
        has_pos: payload.has_pos.unwrap_or(true),
    };

    usahas.push(new_usaha.clone());
    drop(usahas);

    // Audit Log
    let mut logs = state.audit_logs.write().await;
    let log_id = (logs.len() as i64) + 1;
    logs.push(AuditLogModel {
        id: log_id,
        owner_id,
        aktor: aktor_nama,
        role: aktor_role,
        aksi: "Tambah Unit Usaha".to_string(),
        modul: "Unit Usaha".to_string(),
        target: payload.nama,
        detail: format!("Berhasil membuat unit usaha baru ID #{}", new_id),
        waktu: Local::now().format("%Y-%m-%d %H:%M").to_string(),
    });

        (
            StatusCode::CREATED,
            Json(ApiResponse::<UsahaModel> {
                status: "success".to_string(),
                message: "Unit usaha baru berhasil didaftarkan.".to_string(),
                data: Some(new_usaha),
            }),
        ).into_response()
}

// 4. UPDATE UNIT USAHA (Dilindungi Validasi IDOR)
pub async fn update_usaha(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateUsahaRequest>,
) -> impl IntoResponse {
    let claims = match crate::auth::require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };

    // Validasi apakah unit ini benar-benar milik owner yang sedang login
    let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM business_units WHERE id = $1 AND owner_id = $2)")
        .bind(id as i32)
        .bind(claims.owner_id as i32)
        .fetch_one(&state.db)
        .await
        .unwrap_or(false);

    if !exists {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<UsahaModel> {
                status: "error".to_string(),
                message: "Akses ditolak: Anda tidak memiliki izin untuk mengedit unit usaha ini.".to_string(),
                data: None,
            }),
        ).into_response();
    }

    let mut usahas = state.usahas.write().await;
    if let Some(u) = usahas.iter_mut().find(|u| u.id == id && u.owner_id == claims.owner_id) {
        if let Some(nama) = payload.nama { u.nama = nama; }
        if let Some(jenis) = payload.jenis_usaha { u.jenis_usaha = jenis; }
        if let Some(lokasi) = payload.lokasi { u.lokasi = lokasi; }
        if let Some(kat) = payload.kategori_portofolio { u.kategori_portofolio = kat; }
        if let Some(status) = payload.status { u.status = status; }
        if let Some(has_pos) = payload.has_pos { u.has_pos = has_pos; }

        let _ = sqlx::query(
            "UPDATE business_units SET nama = $1, jenis_usaha = $2, lokasi = $3, kategori_portofolio = $4, status = $5, has_pos = $6 WHERE id = $7 AND owner_id = $8"
        )
        .bind(&u.nama)
        .bind(&u.jenis_usaha)
        .bind(&u.lokasi)
        .bind(&u.kategori_portofolio)
        .bind(u.status)
        .bind(u.has_pos)
        .bind(id as i32)
        .bind(claims.owner_id as i32)
        .execute(&state.db)
        .await;

        return (
            StatusCode::OK,
            Json(ApiResponse::<UsahaModel> {
                status: "success".to_string(),
                message: "Data unit usaha berhasil diperbarui.".to_string(),
                data: Some(u.clone()),
            }),
        ).into_response();
    }

    (
        StatusCode::NOT_FOUND,
        Json(ApiResponse::<UsahaModel> {
            status: "error".to_string(),
            message: "Unit usaha tidak ditemukan.".to_string(),
            data: None,
        }),
    ).into_response()
}

// 5. TOGGLE STATUS POS (Dilindungi Validasi IDOR)
pub async fn toggle_pos(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let claims = match crate::auth::require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };

    let mut usahas = state.usahas.write().await;
    if let Some(u) = usahas.iter_mut().find(|u| u.id == id && u.owner_id == claims.owner_id) {
        u.has_pos = !u.has_pos;
        let status_str = if u.has_pos { "Aktif" } else { "Non-Aktif" };

        let _ = sqlx::query("UPDATE business_units SET has_pos = $1 WHERE id = $2 AND owner_id = $3")
            .bind(u.has_pos)
            .bind(id as i32)
            .bind(claims.owner_id as i32)
            .execute(&state.db)
            .await;

        return (
            StatusCode::OK,
            Json(ApiResponse::<UsahaModel> {
                status: "success".to_string(),
                message: format!("Fitur Kasir POS untuk {} kini: {}", u.nama, status_str),
                data: Some(u.clone()),
            }),
        ).into_response();
    }

    (
        StatusCode::FORBIDDEN,
        Json(ApiResponse::<UsahaModel> {
            status: "error".to_string(),
            message: "Unit usaha tidak ditemukan atau Anda tidak memiliki hak akses.".to_string(),
            data: None,
        }),
    ).into_response()
}

// 6. HAPUS UNIT USAHA (Dilindungi Validasi IDOR)
pub async fn delete_usaha(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let claims = match crate::auth::require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };

    let res = sqlx::query("DELETE FROM business_units WHERE id = $1 AND owner_id = $2")
        .bind(id as i32)
        .bind(claims.owner_id as i32)
        .execute(&state.db)
        .await;

    match res {
        Ok(r) if r.rows_affected() > 0 => {
            let mut usahas = state.usahas.write().await;
            usahas.retain(|u| u.id != id);

            (
                StatusCode::OK,
                Json(ApiResponse::<()> {
                    status: "success".to_string(),
                    message: format!("Unit usaha #{} berhasil dihapus permanen.", id),
                    data: None,
                }),
            ).into_response()
        }
        _ => (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Gagal menghapus: Unit usaha tidak ditemukan atau Anda bukan pemilik unit ini.".to_string(),
                data: None,
            }),
        ).into_response(),
    }
}
