use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use bcrypt::hash;
use std::sync::Arc;
use chrono::Local;

use crate::auth::extract_claims;
use crate::models::{AuditLogModel, KaryawanAccount};
use crate::schemas::{ApiResponse, CreateKaryawanRequest, UpdateKaryawanRequest};
use crate::state::AppState;

// 1. LIST KARYAWAN (Hanya milik Owner terkait)
pub async fn list_karyawan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    let karyawans = state.karyawans.read().await;
    let hasil: Vec<KaryawanAccount> = karyawans
        .iter()
        .filter(|k| k.owner_id == owner_id)
        .cloned()
        .collect();

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<KaryawanAccount>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} akun karyawan.", hasil.len()),
            data: Some(hasil),
        }),
    )
}

// 2. TAMBAH KARYAWAN (Hanya Owner yang berhak mendaftarkan karyawan)
pub async fn create_karyawan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateKaryawanRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);
    let aktor_nama = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "Owner".to_string());

    let mut karyawans = state.karyawans.write().await;

    // Cek duplikasi email
    if karyawans.iter().any(|k| k.email.to_lowercase() == payload.email.to_lowercase()) {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<KaryawanAccount> {
                status: "error".to_string(),
                message: "Email karyawan sudah terdaftar.".to_string(),
                data: None,
            }),
        );
    }

    let password_hash = hash(&payload.password, 4).unwrap_or_default();
    let new_id = (karyawans.len() as i64) + 1;

    let new_karyawan = KaryawanAccount {
        id: new_id,
        owner_id,
        nama: payload.nama.clone(),
        email: payload.email,
        password_hash,
        peran: payload.peran.clone(),
        unit_akses_ids: payload.unit_akses_ids,
        is_active: true,
    };

    karyawans.push(new_karyawan.clone());
    drop(karyawans);

    // Audit Log
    let mut logs = state.audit_logs.write().await;
    let log_id = (logs.len() as i64) + 1;
    logs.push(AuditLogModel {
        id: log_id,
        owner_id,
        aktor: aktor_nama,
        role: "owner".to_string(),
        aksi: "Daftarkan Karyawan".to_string(),
        modul: "Pengguna".to_string(),
        target: payload.nama,
        detail: format!("Membuat akun karyawan baru dengan peran {:?}", payload.peran),
        waktu: Local::now().format("%Y-%m-%d %H:%M").to_string(),
    });

    (
        StatusCode::CREATED,
        Json(ApiResponse::<KaryawanAccount> {
            status: "success".to_string(),
            message: "Karyawan baru berhasil didaftarkan dan dapat langsung login.".to_string(),
            data: Some(new_karyawan),
        }),
    )
}

// 3. UPDATE KARYAWAN (Peran / Akses Unit)
pub async fn update_karyawan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateKaryawanRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);
    let aktor_nama = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "Owner".to_string());

    let mut karyawans = state.karyawans.write().await;

    if let Some(k) = karyawans.iter_mut().find(|k| k.id == id && k.owner_id == owner_id) {
        if let Some(nama) = payload.nama {
            k.nama = nama;
        }
        if let Some(peran) = payload.peran {
            k.peran = peran;
        }
        if let Some(unit_ids) = payload.unit_akses_ids {
            k.unit_akses_ids = unit_ids;
        }
        if let Some(active) = payload.is_active {
            k.is_active = active;
        }

        let updated = k.clone();
        drop(karyawans);

        // Audit Log
        let mut logs = state.audit_logs.write().await;
        let log_id = (logs.len() as i64) + 1;
        logs.push(AuditLogModel {
            id: log_id,
            owner_id,
            aktor: aktor_nama,
            role: "owner".to_string(),
            aksi: "Update Karyawan".to_string(),
            modul: "Pengguna".to_string(),
            target: updated.nama.clone(),
            detail: format!("Memperbarui hak akses dan status karyawan ID #{}", id),
            waktu: Local::now().format("%Y-%m-%d %H:%M").to_string(),
        });

        return (
            StatusCode::OK,
            Json(ApiResponse::<KaryawanAccount> {
                status: "success".to_string(),
                message: "Data karyawan berhasil diperbarui.".to_string(),
                data: Some(updated),
            }),
        );
    }

    (
        StatusCode::NOT_FOUND,
        Json(ApiResponse::<KaryawanAccount> {
            status: "error".to_string(),
            message: "Akun karyawan tidak ditemukan.".to_string(),
            data: None,
        }),
    )
}

// 4. HAPUS / NON-AKTIFKAN KARYAWAN
pub async fn delete_karyawan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);
    let aktor_nama = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "Owner".to_string());

    let mut karyawans = state.karyawans.write().await;
    let initial_len = karyawans.len();
    karyawans.retain(|k| !(k.id == id && k.owner_id == owner_id));

    if karyawans.len() < initial_len {
        drop(karyawans);

        // Audit Log
        let mut logs = state.audit_logs.write().await;
        let log_id = (logs.len() as i64) + 1;
        logs.push(AuditLogModel {
            id: log_id,
            owner_id,
            aktor: aktor_nama,
            role: "owner".to_string(),
            aksi: "Hapus Karyawan".to_string(),
            modul: "Pengguna".to_string(),
            target: format!("Karyawan #{}", id),
            detail: "Menghapus akses akun karyawan dari sistem".to_string(),
            waktu: Local::now().format("%Y-%m-%d %H:%M").to_string(),
        });

        (
            StatusCode::OK,
            Json(ApiResponse::<()> {
                status: "success".to_string(),
                message: format!("Akun karyawan #{} berhasil dihapus.", id),
                data: None,
            }),
        )
    } else {
        (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Akun karyawan tidak ditemukan.".to_string(),
                data: None,
            }),
        )
    }
}

// 5. LIST AUDIT TRAIL / LOG AKTIVITAS
pub async fn list_audit_logs(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    let logs = state.audit_logs.read().await;
    let hasil: Vec<AuditLogModel> = logs
        .iter()
        .filter(|l| l.owner_id == owner_id)
        .rev() // Terkini paling atas
        .cloned()
        .collect();

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<AuditLogModel>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} catatan audit log.", hasil.len()),
            data: Some(hasil),
        }),
    )
}
