use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use std::sync::Arc;
use chrono::Local;

use crate::auth::extract_claims;
use crate::models::{AuditLogModel, UsahaModel};
use crate::schemas::{ApiResponse, CreateUsahaRequest, UpdateUsahaRequest};
use crate::state::AppState;

// 1. LIST UNIT USAHA
pub async fn list_usaha(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);
    let role = claims.as_ref().map(|c| c.role.as_str()).unwrap_or("owner");

    let usahas = state.usahas.read().await;

    // Filter berdasarkan owner
    let mut hasil: Vec<UsahaModel> = usahas
        .iter()
        .filter(|u| u.owner_id == owner_id)
        .cloned()
        .collect();

    // Jika karyawan dengan hak akses terbatas, filter unit_id
    if role != "owner" && role != "auditor" {
        if let Some(c) = &claims {
            let karyawans = state.karyawans.read().await;
            if let Some(k) = karyawans.iter().find(|k| k.id == c.user_id) {
                if !k.unit_akses_ids.is_empty() {
                    hasil.retain(|u| k.unit_akses_ids.contains(&u.id));
                }
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
    )
}

// 2. DETAIL UNIT USAHA
pub async fn get_usaha_detail(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let usahas = state.usahas.read().await;

    match usahas.iter().find(|u| u.id == id) {
        Some(u) => (
            StatusCode::OK,
            Json(ApiResponse::<UsahaModel> {
                status: "success".to_string(),
                message: "Detail unit usaha ditemukan.".to_string(),
                data: Some(u.clone()),
            }),
        ),
        None => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<UsahaModel> {
                status: "error".to_string(),
                message: "Unit usaha tidak ditemukan.".to_string(),
                data: None,
            }),
        ),
    }
}

// 3. TAMBAH UNIT USAHA (Cek Kuota Tier Langganan)
pub async fn create_usaha(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateUsahaRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);
    let aktor_nama = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "Owner Demo".to_string());
    let aktor_role = claims.as_ref().map(|c| c.role.clone()).unwrap_or_else(|| "owner".to_string());

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
            );
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
        );
    }

    let new_id = (usahas.len() as i64) + 1;
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
    )
}

// 4. UPDATE UNIT USAHA
pub async fn update_usaha(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateUsahaRequest>,
) -> impl IntoResponse {
    let mut usahas = state.usahas.write().await;

    if let Some(u) = usahas.iter_mut().find(|u| u.id == id) {
        if let Some(nama) = payload.nama {
            u.nama = nama;
        }
        if let Some(jenis) = payload.jenis_usaha {
            u.jenis_usaha = jenis;
        }
        if let Some(lokasi) = payload.lokasi {
            u.lokasi = lokasi;
        }
        if let Some(kat) = payload.kategori_portofolio {
            u.kategori_portofolio = kat;
        }
        if let Some(status) = payload.status {
            u.status = status;
        }
        if let Some(has_pos) = payload.has_pos {
            u.has_pos = has_pos;
        }

        return (
            StatusCode::OK,
            Json(ApiResponse::<UsahaModel> {
                status: "success".to_string(),
                message: "Data unit usaha berhasil diperbarui.".to_string(),
                data: Some(u.clone()),
            }),
        );
    }

    (
        StatusCode::NOT_FOUND,
        Json(ApiResponse::<UsahaModel> {
            status: "error".to_string(),
            message: "Unit usaha tidak ditemukan.".to_string(),
            data: None,
        }),
    )
}

// 5. TOGGLE STATUS POS
pub async fn toggle_pos(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let mut usahas = state.usahas.write().await;

    if let Some(u) = usahas.iter_mut().find(|u| u.id == id) {
        u.has_pos = !u.has_pos;
        let status_str = if u.has_pos { "Aktif" } else { "Non-Aktif" };

        return (
            StatusCode::OK,
            Json(ApiResponse::<UsahaModel> {
                status: "success".to_string(),
                message: format!("Fitur Kasir POS untuk {} kini: {}", u.nama, status_str),
                data: Some(u.clone()),
            }),
        );
    }

    (
        StatusCode::NOT_FOUND,
        Json(ApiResponse::<UsahaModel> {
            status: "error".to_string(),
            message: "Unit usaha tidak ditemukan.".to_string(),
            data: None,
        }),
    )
}

// 6. HAPUS UNIT USAHA
pub async fn delete_usaha(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let mut usahas = state.usahas.write().await;
    let initial_len = usahas.len();
    usahas.retain(|u| u.id != id);

    if usahas.len() < initial_len {
        (
            StatusCode::OK,
            Json(ApiResponse::<()> {
                status: "success".to_string(),
                message: format!("Unit usaha #{} berhasil dihapus.", id),
                data: None,
            }),
        )
    } else {
        (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Unit usaha tidak ditemukan.".to_string(),
                data: None,
            }),
        )
    }
}
