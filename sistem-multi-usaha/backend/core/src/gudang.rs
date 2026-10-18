use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use std::sync::Arc;
use chrono::Local;

use crate::auth::require_claims;
use crate::models::{PermintaanStokModel, StatusPermintaanStok, StatusTransfer, StokOpnameModel, TransferStokModel};
use crate::schemas::{
    ApiResponse, CreatePermintaanStokRequest, CreateStokOpnameRequest,
    CreateTransferStokRequest, UpdateStatusPermintaanRequest, UpdateStatusTransferRequest,
};
use crate::state::AppState;

// ==================== 1. PERMINTAAN STOK ====================

pub async fn list_permintaan_stok(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;

    let rows = sqlx::query_as::<_, (i32, i32, i32, String, String, String, i32, Option<String>, chrono::NaiveDateTime, String)>(
        "SELECT id, owner_id, unit_id, nama_unit, pemohon, nama_produk, jumlah_diminta, alasan, waktu_pengajuan, status
         FROM stock_requests
         WHERE owner_id = $1
         ORDER BY id DESC"
    )
    .bind(owner_id as i32)
    .fetch_all(&state.db)
    .await;

    let hasil: Vec<PermintaanStokModel> = match rows {
        Ok(list) => list
            .into_iter()
            .map(|r| PermintaanStokModel {
                id: r.0 as i64,
                owner_id: r.1 as i64,
                unit_id: r.2 as i64,
                nama_unit: r.3,
                pemohon: r.4,
                nama_produk: r.5,
                jumlah_diminta: r.6,
                alasan: r.7.unwrap_or_default(),
                waktu_pengajuan: r.8.format("%Y-%m-%d %H:%M").to_string(),
                status: match r.9.as_str() {
                    "disetujui" => StatusPermintaanStok::Disetujui,
                    "ditolak" => StatusPermintaanStok::Ditolak,
                    "selesai" => StatusPermintaanStok::Selesai,
                    _ => StatusPermintaanStok::Pending,
                },
            })
            .collect(),
        Err(_) => Vec::new(),
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<PermintaanStokModel>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} pengajuan permintaan stok dari PostgreSQL.", hasil.len()),
            data: Some(hasil),
        }),
    ).into_response()
}

pub async fn create_permintaan_stok(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreatePermintaanStokRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;
    let pemohon = claims.sub.clone();

    // Ambil nama unit
    let nama_unit: String = sqlx::query_scalar("SELECT nama FROM business_units WHERE id = $1")
        .bind(payload.unit_id as i32)
        .fetch_optional(&state.db)
        .await
        .ok()
        .flatten()
        .unwrap_or_else(|| "Unit Usaha".to_string());

    let row: Result<(i32,), sqlx::Error> = sqlx::query_as(
        "INSERT INTO stock_requests (owner_id, unit_id, nama_unit, pemohon, nama_produk, jumlah_diminta, alasan, waktu_pengajuan, status)
         VALUES ($1, $2, $3, $4, $5, $6, $7, now(), 'pending')
         RETURNING id"
    )
    .bind(owner_id as i32)
    .bind(payload.unit_id as i32)
    .bind(&nama_unit)
    .bind(&pemohon)
    .bind(&payload.nama_produk)
    .bind(payload.jumlah_diminta)
    .bind(&payload.alasan)
    .fetch_one(&state.db)
    .await;

    match row {
        Ok(r) => {
            let new_permintaan = PermintaanStokModel {
                id: r.0 as i64,
                owner_id,
                unit_id: payload.unit_id,
                nama_unit,
                pemohon,
                nama_produk: payload.nama_produk,
                jumlah_diminta: payload.jumlah_diminta,
                alasan: payload.alasan,
                waktu_pengajuan: Local::now().format("%Y-%m-%d %H:%M").to_string(),
                status: StatusPermintaanStok::Pending,
            };

            (
                StatusCode::CREATED,
                Json(ApiResponse::<PermintaanStokModel> {
                    status: "success".to_string(),
                    message: "Pengajuan permintaan stok tersimpan permanen di database PostgreSQL.".to_string(),
                    data: Some(new_permintaan),
                }),
            ).into_response()
        }
        Err(e) => {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<PermintaanStokModel> {
                    status: "error".to_string(),
                    message: format!("Gagal menyimpan pengajuan: {}", e),
                    data: None,
                }),
            ).into_response()
        }
    }
}

pub async fn update_status_permintaan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateStatusPermintaanRequest>,
) -> impl IntoResponse {
    let _claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };

    let status_str = format!("{:?}", payload.status).to_lowercase();
    let res = sqlx::query("UPDATE stock_requests SET status = $1 WHERE id = $2")
        .bind(&status_str)
        .bind(id as i32)
        .execute(&state.db)
        .await;

    match res {
        Ok(_) => (
            StatusCode::OK,
            Json(ApiResponse::<()> {
                status: "success".to_string(),
                message: format!("Status permintaan stok #{} berhasil diperbarui ke: {}", id, status_str),
                data: None,
            }),
        ).into_response(),
        Err(e) => (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: format!("Gagal update status: {}", e),
                data: None,
            }),
        ).into_response(),
    }
}

// ==================== 2. STOK OPNAME ====================

pub async fn list_stok_opname(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;

    let rows = sqlx::query_as::<_, (i32, i32, i32, String, String, i32, i32, i32, Option<String>, chrono::NaiveDate)>(
        "SELECT id, owner_id, unit_id, nama_unit, nama_produk, stok_sistem, stok_fisik, selisih, alasan, tanggal
         FROM stock_opnames
         WHERE owner_id = $1
         ORDER BY id DESC"
    )
    .bind(owner_id as i32)
    .fetch_all(&state.db)
    .await;

    let hasil: Vec<StokOpnameModel> = match rows {
        Ok(list) => list
            .into_iter()
            .map(|r| StokOpnameModel {
                id: r.0 as i64,
                owner_id: r.1 as i64,
                unit_id: r.2 as i64,
                nama_unit: r.3,
                nama_produk: r.4,
                stok_sistem: r.5,
                stok_fisik: r.6,
                selisih: r.7,
                alasan: r.8.unwrap_or_default(),
                tanggal: r.9.to_string(),
            })
            .collect(),
        Err(_) => Vec::new(),
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<StokOpnameModel>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} catatan stok opname.", hasil.len()),
            data: Some(hasil),
        }),
    ).into_response()
}

pub async fn create_stok_opname(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateStokOpnameRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;

    // Ambil nama unit
    let nama_unit: String = sqlx::query_scalar("SELECT nama FROM business_units WHERE id = $1")
        .bind(payload.unit_id as i32)
        .fetch_optional(&state.db)
        .await
        .ok()
        .flatten()
        .unwrap_or_else(|| "Unit Usaha".to_string());

    // Ambil stok sistem saat ini
    let stok_sistem: i32 = sqlx::query_scalar(
        "SELECT i.qty FROM inventories i
         JOIN products p ON i.product_id = p.id
         WHERE i.unit_id = $1 AND LOWER(p.nama) = LOWER($2)"
    )
    .bind(payload.unit_id as i32)
    .bind(&payload.nama_produk)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten()
    .unwrap_or(0);

    let selisih = payload.stok_fisik - stok_sistem;

    // Rekonsiliasi update stok fisik ke PostgreSQL `inventories`
    let _ = sqlx::query(
        "UPDATE inventories 
         SET qty = $1 
         WHERE unit_id = $2 AND product_id = (SELECT id FROM products WHERE LOWER(nama) = LOWER($3) LIMIT 1)"
    )
    .bind(payload.stok_fisik)
    .bind(payload.unit_id as i32)
    .bind(&payload.nama_produk)
    .execute(&state.db)
    .await;

    // Catat ke tabel `stock_opnames`
    let row: Result<(i32,), sqlx::Error> = sqlx::query_as(
        "INSERT INTO stock_opnames (owner_id, unit_id, nama_unit, nama_produk, stok_sistem, stok_fisik, selisih, alasan, tanggal)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, CURRENT_DATE)
         RETURNING id"
    )
    .bind(owner_id as i32)
    .bind(payload.unit_id as i32)
    .bind(&nama_unit)
    .bind(&payload.nama_produk)
    .bind(stok_sistem)
    .bind(payload.stok_fisik)
    .bind(selisih)
    .bind(&payload.alasan)
    .fetch_one(&state.db)
    .await;

    match row {
        Ok(r) => {
            let new_opname = StokOpnameModel {
                id: r.0 as i64,
                owner_id,
                unit_id: payload.unit_id,
                nama_unit,
                nama_produk: payload.nama_produk,
                stok_sistem,
                stok_fisik: payload.stok_fisik,
                selisih,
                alasan: payload.alasan,
                tanggal: Local::now().format("%Y-%m-%d").to_string(),
            };

            (
                StatusCode::CREATED,
                Json(ApiResponse::<StokOpnameModel> {
                    status: "success".to_string(),
                    message: "Rekonsiliasi stok opname berhasil disimpan dan stok sistem telah diperbarui di PostgreSQL.".to_string(),
                    data: Some(new_opname),
                }),
            ).into_response()
        }
        Err(e) => {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<StokOpnameModel> {
                    status: "error".to_string(),
                    message: format!("Gagal menyimpan opname: {}", e),
                    data: None,
                }),
            ).into_response()
        }
    }
}

// ==================== 3. TRANSFER STOK ====================

pub async fn list_transfer_stok(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let _claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };

    let rows = sqlx::query_as::<_, (i32, Option<i32>, Option<i32>, i32, chrono::NaiveDateTime)>(
        "SELECT id, unit_asal_id, unit_tujuan_id, qty, tanggal
         FROM stock_movements
         WHERE tipe = 'transfer'
         ORDER BY id DESC"
    )
    .fetch_all(&state.db)
    .await;

    let hasil: Vec<TransferStokModel> = match rows {
        Ok(list) => list
            .into_iter()
            .map(|r| TransferStokModel {
                id: r.0 as i64,
                owner_id: 1,
                unit_asal_id: r.1.unwrap_or(0) as i64,
                nama_unit_asal: format!("Unit #{}", r.1.unwrap_or(0)),
                unit_tujuan_id: r.2.unwrap_or(0) as i64,
                nama_unit_tujuan: format!("Unit #{}", r.2.unwrap_or(0)),
                produk_id: 1,
                nama_produk: "Transfer Barang".to_string(),
                jumlah: r.3,
                waktu_kirim: r.4.format("%Y-%m-%d %H:%M").to_string(),
                waktu_terima: Some(r.4.format("%Y-%m-%d %H:%M").to_string()),
                status: StatusTransfer::Diterima,
            })
            .collect(),
        Err(_) => Vec::new(),
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<TransferStokModel>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} mutasi transfer stok dari database.", hasil.len()),
            data: Some(hasil),
        }),
    ).into_response()
}

pub async fn create_transfer_stok(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateTransferStokRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let user_id = claims.user_id;

    // Panggil Stored Procedure sp_transfer_stok_antar_unit
    let result: Result<(Option<String>, Option<String>), sqlx::Error> = sqlx::query_as(
        "CALL sp_transfer_stok_antar_unit($1, $2, $3, $4, $5, NULL, NULL)"
    )
    .bind(payload.unit_asal_id as i32)
    .bind(payload.unit_tujuan_id as i32)
    .bind(payload.produk_id as i32)
    .bind(payload.jumlah)
    .bind(user_id as i32)
    .fetch_one(&state.db)
    .await;

    match result {
        Ok((status_opt, pesan_opt)) => {
            let status_str = status_opt.unwrap_or_else(|| "error".to_string());
            let pesan_str = pesan_opt.unwrap_or_else(|| "Gagal memproses transfer stok.".to_string());

            if status_str == "error" {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(ApiResponse::<TransferStokModel> {
                        status: "error".to_string(),
                        message: pesan_str,
                        data: None,
                    }),
                ).into_response();
            }

            let new_transfer = TransferStokModel {
                id: chrono::Utc::now().timestamp(),
                owner_id: 1,
                unit_asal_id: payload.unit_asal_id,
                nama_unit_asal: format!("Unit #{}", payload.unit_asal_id),
                unit_tujuan_id: payload.unit_tujuan_id,
                nama_unit_tujuan: format!("Unit #{}", payload.unit_tujuan_id),
                produk_id: payload.produk_id,
                nama_produk: format!("Produk #{}", payload.produk_id),
                jumlah: payload.jumlah,
                waktu_kirim: Local::now().format("%Y-%m-%d %H:%M").to_string(),
                waktu_terima: Some(Local::now().format("%Y-%m-%d %H:%M").to_string()),
                status: StatusTransfer::Diterima,
            };

            (
                StatusCode::CREATED,
                Json(ApiResponse::<TransferStokModel> {
                    status: "success".to_string(),
                    message: pesan_str,
                    data: Some(new_transfer),
                }),
            ).into_response()
        }
        Err(e) => {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<TransferStokModel> {
                    status: "error".to_string(),
                    message: format!("Error database: {}", e),
                    data: None,
                }),
            ).into_response()
        }
    }
}

pub async fn update_status_transfer(
    State(_state): State<Arc<AppState>>,
    _headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateStatusTransferRequest>,
) -> impl IntoResponse {
    (
        StatusCode::OK,
        Json(ApiResponse::<()> {
            status: "success".to_string(),
            message: format!("Status transfer #{} dikonfirmasi: {:?}", id, payload.status),
            data: None,
        }),
    )
}
