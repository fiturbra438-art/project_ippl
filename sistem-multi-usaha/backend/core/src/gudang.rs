use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use chrono::Local;
use std::sync::Arc;

use crate::auth::{accessible_unit_ids, ensure_roles, ensure_unit_access};
use crate::models::{
    Claims, PermintaanStokModel, StatusPermintaanStok, StatusTransfer, StokOpnameModel,
    TransferStokModel,
};
use crate::schemas::{
    ApiResponse, CreatePermintaanStokRequest, CreateStokOpnameRequest, CreateTransferStokRequest,
    UpdateStatusPermintaanRequest, UpdateStatusTransferRequest,
};
use crate::state::AppState;

#[derive(sqlx::FromRow)]
struct TransferRow {
    id: i32,
    unit_asal_id: i32,
    unit_tujuan_id: i32,
    jumlah: i32,
    tanggal: chrono::NaiveDateTime,
    nama_unit_asal: String,
    nama_unit_tujuan: String,
    nama_produk: String,
    produk_id: i32,
    status: String,
    waktu_terima: Option<chrono::NaiveDateTime>,
    pemohon: Option<String>,
    disetujui_oleh: Option<String>,
    waktu_persetujuan: Option<chrono::NaiveDateTime>,
    dikirim_oleh: Option<String>,
    waktu_pengiriman: Option<chrono::NaiveDateTime>,
    diterima_oleh: Option<String>,
    alasan_penolakan: Option<String>,
    dibatalkan_oleh: Option<String>,
    waktu_pembatalan: Option<chrono::NaiveDateTime>,
}

fn valid_transfer_transition(current: &str, next: &str) -> bool {
    matches!(
        (current, next),
        ("pending", "disetujui" | "ditolak" | "dibatalkan")
            | ("disetujui", "dikirim" | "ditolak" | "dibatalkan")
            | ("dikirim", "diterima")
    )
}

fn transfer_stock_available(stock: i32, reserved: i32, requested: i32) -> bool {
    requested > 0 && reserved >= 0 && stock >= reserved && stock - reserved >= requested
}

fn transfer_role_allowed(role: &str) -> bool {
    ["owner", "manager", "admin_gudang"].contains(&role)
}

// ==================== 1. PERMINTAAN STOK ====================

pub async fn list_permintaan_stok(
    State(state): State<Arc<AppState>>,
    claims: Claims,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;
    let unit_ids = match accessible_unit_ids(&state, &claims).await {
        Ok(ids) => ids,
        Err(response) => return response.into_response(),
    };

    let rows = sqlx::query_as::<_, (i32, i32, i32, String, String, String, i32, Option<String>, chrono::NaiveDateTime, String)>(
        "SELECT id, owner_id, unit_id, nama_unit, pemohon, nama_produk, jumlah_diminta, alasan, waktu_pengajuan, status
         FROM stock_requests
         WHERE owner_id = $1 AND unit_id = ANY($2)
         ORDER BY id DESC"
    )
    .bind(owner_id as i32)
    .bind(&unit_ids)
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
            message: format!(
                "Berhasil mengambil {} pengajuan permintaan stok dari PostgreSQL.",
                hasil.len()
            ),
            data: Some(hasil),
        }),
    )
        .into_response()
}

pub async fn create_permintaan_stok(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Json(payload): Json<CreatePermintaanStokRequest>,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;
    let pemohon = claims.sub.clone();
    if let Err(response) = ensure_unit_access(&state, &claims, payload.unit_id).await {
        return response.into_response();
    }

    let unit_valid: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM business_units WHERE id = $1 AND owner_id = $2)",
    )
    .bind(payload.unit_id as i32)
    .bind(owner_id as i32)
    .fetch_one(&state.db)
    .await
    .unwrap_or(false);
    if !unit_valid {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<PermintaanStokModel> {
                status: "error".to_string(),
                message: "Unit usaha bukan milik bisnis Anda.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

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
                    message: "Pengajuan permintaan stok tersimpan permanen di database PostgreSQL."
                        .to_string(),
                    data: Some(new_permintaan),
                }),
            )
                .into_response()
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<PermintaanStokModel> {
                status: "error".to_string(),
                message: format!("Gagal menyimpan pengajuan: {}", e),
                data: None,
            }),
        )
            .into_response(),
    }
}

pub async fn update_status_permintaan(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateStatusPermintaanRequest>,
) -> impl IntoResponse {
    if !transfer_role_allowed(&claims.role) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<TransferStokModel> {
                status: "error".to_string(),
                message: "Role tidak berwenang mengajukan transfer stok.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    let allowed: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM stock_requests r WHERE r.id = $1 AND r.owner_id = $2 AND EXISTS(SELECT 1 FROM business_units u WHERE u.id = r.unit_id AND ($3 OR EXISTS(SELECT 1 FROM user_units uu WHERE uu.user_id = $4 AND uu.unit_id = u.id))))")
        .bind(id as i32).bind(claims.owner_id as i32).bind(claims.role == "owner").bind(claims.user_id)
        .fetch_one(&state.db).await.unwrap_or(false);
    if !allowed {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Akses permintaan stok ditolak.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    let status_str = format!("{:?}", payload.status).to_lowercase();
    let res = sqlx::query("UPDATE stock_requests SET status = $1 WHERE id = $2 AND owner_id = $3")
        .bind(&status_str)
        .bind(id as i32)
        .bind(claims.owner_id as i32)
        .execute(&state.db)
        .await;

    match res {
        Ok(_) => (
            StatusCode::OK,
            Json(ApiResponse::<()> {
                status: "success".to_string(),
                message: format!(
                    "Status permintaan stok #{} berhasil diperbarui ke: {}",
                    id, status_str
                ),
                data: None,
            }),
        )
            .into_response(),
        Err(e) => (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: format!("Gagal update status: {}", e),
                data: None,
            }),
        )
            .into_response(),
    }
}

// ==================== 2. STOK OPNAME ====================

pub async fn list_stok_opname(
    State(state): State<Arc<AppState>>,
    claims: Claims,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;
    let unit_ids = match accessible_unit_ids(&state, &claims).await {
        Ok(ids) => ids,
        Err(response) => return response.into_response(),
    };

    let rows = sqlx::query_as::<_, (i32, i32, i32, i32, String, String, i32, i32, i32, Option<String>, chrono::NaiveDate)>(
        "SELECT id, owner_id, unit_id, product_id, nama_unit, nama_produk, stok_sistem, stok_fisik, selisih, alasan, tanggal
         FROM stock_opnames
         WHERE owner_id = $1 AND unit_id = ANY($2)
         ORDER BY id DESC"
    )
    .bind(owner_id as i32)
    .bind(&unit_ids)
    .fetch_all(&state.db)
    .await;

    let hasil: Vec<StokOpnameModel> = match rows {
        Ok(list) => list
            .into_iter()
            .map(|r| StokOpnameModel {
                id: r.0 as i64,
                owner_id: r.1 as i64,
                unit_id: r.2 as i64,
                product_id: r.3 as i64,
                nama_unit: r.4,
                nama_produk: r.5,
                stok_sistem: r.6,
                stok_fisik: r.7,
                selisih: r.8,
                alasan: r.9.unwrap_or_default(),
                tanggal: r.10.to_string(),
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
    )
        .into_response()
}

pub async fn create_stok_opname(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Json(payload): Json<CreateStokOpnameRequest>,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;
    if !["owner", "manager", "admin_gudang"].contains(&claims.role.as_str()) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<StokOpnameModel> {
                status: "error".to_string(),
                message: "Role tidak boleh mencatat stok opname.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    if let Err(response) = ensure_unit_access(&state, &claims, payload.unit_id).await {
        return response.into_response();
    }

    let unit_valid: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM business_units WHERE id = $1 AND owner_id = $2)",
    )
    .bind(payload.unit_id as i32)
    .bind(owner_id as i32)
    .fetch_one(&state.db)
    .await
    .unwrap_or(false);
    if !unit_valid {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<StokOpnameModel> {
                status: "error".to_string(),
                message: "Unit usaha bukan milik bisnis Anda.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    if payload.stok_fisik < 0 {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<StokOpnameModel> {
                status: "error".to_string(),
                message: "Stok fisik tidak boleh bernilai negatif.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    // Ambil nama unit
    let nama_unit: String = sqlx::query_scalar("SELECT nama FROM business_units WHERE id = $1")
        .bind(payload.unit_id as i32)
        .fetch_optional(&state.db)
        .await
        .ok()
        .flatten()
        .unwrap_or_else(|| "Unit Usaha".to_string());

    let product_name: Option<String> = sqlx::query_scalar(
        "SELECT p.nama FROM products p JOIN inventories i ON i.product_id = p.id WHERE p.id = $1 AND p.owner_id = $2 AND i.unit_id = $3",
    )
    .bind(payload.product_id as i32)
    .bind(owner_id as i32)
    .bind(payload.unit_id as i32)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten();
    let product_name = match product_name {
        Some(name) => name,
        None => {
            return (
                StatusCode::NOT_FOUND,
                Json(ApiResponse::<StokOpnameModel> {
                    status: "error".to_string(),
                    message: "Produk tidak ditemukan pada unit.".to_string(),
                    data: None,
                }),
            )
                .into_response()
        }
    };
    let stok_sistem: i32 =
        sqlx::query_scalar("SELECT qty FROM inventories WHERE unit_id = $1 AND product_id = $2")
            .bind(payload.unit_id as i32)
            .bind(payload.product_id as i32)
            .fetch_optional(&state.db)
            .await
            .ok()
            .flatten()
            .unwrap_or(0);

    let selisih = payload.stok_fisik - stok_sistem;

    let update_result =
        sqlx::query("UPDATE inventories SET qty = $1 WHERE unit_id = $2 AND product_id = $3")
            .bind(payload.stok_fisik)
            .bind(payload.unit_id as i32)
            .bind(payload.product_id as i32)
            .execute(&state.db)
            .await;
    if let Err(e) = update_result {
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<StokOpnameModel> {
                status: "error".to_string(),
                message: format!("Gagal memperbarui stok: {}", e),
                data: None,
            }),
        )
            .into_response();
    }

    // Catat ke tabel `stock_opnames`
    let row: Result<(i32,), sqlx::Error> = sqlx::query_as(
        "INSERT INTO stock_opnames (owner_id, unit_id, nama_unit, nama_produk, stok_sistem, stok_fisik, selisih, alasan, tanggal)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, CURRENT_DATE)
         RETURNING id"
    )
    .bind(owner_id as i32)
    .bind(payload.unit_id as i32)
    .bind(&nama_unit)
    .bind(&product_name)
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
                product_id: payload.product_id,
                nama_unit,
                nama_produk: product_name,
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
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<StokOpnameModel> {
                status: "error".to_string(),
                message: format!("Gagal menyimpan opname: {}", e),
                data: None,
            }),
        )
            .into_response(),
    }
}

// ==================== 3. TRANSFER STOK ====================

pub async fn list_transfer_stok(
    State(state): State<Arc<AppState>>,
    claims: Claims,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;
    let unit_ids = match accessible_unit_ids(&state, &claims).await {
        Ok(ids) => ids,
        Err(response) => return response.into_response(),
    };

    let rows = sqlx::query_as::<_, TransferRow>(
        "SELECT sm.id, sm.unit_asal_id, sm.unit_tujuan_id, sm.qty AS jumlah, sm.tanggal,
                ua.nama AS nama_unit_asal, ut.nama AS nama_unit_tujuan,
                p.nama AS nama_produk, p.id AS produk_id, sm.status, sm.waktu_terima,
                pemohon.nama AS pemohon, approver.nama AS disetujui_oleh, sm.waktu_persetujuan,
                sender.nama AS dikirim_oleh, sm.waktu_pengiriman,
                receiver.nama AS diterima_oleh, sm.alasan_penolakan,
                canceller.nama AS dibatalkan_oleh, sm.waktu_pembatalan
         FROM stock_movements sm
         JOIN business_units ua ON sm.unit_asal_id = ua.id
         JOIN business_units ut ON sm.unit_tujuan_id = ut.id
         JOIN inventories inv ON sm.inventory_id = inv.id
         JOIN products p ON inv.product_id = p.id
         LEFT JOIN users pemohon ON sm.diminta_oleh = pemohon.id
         LEFT JOIN users approver ON sm.disetujui_oleh = approver.id
         LEFT JOIN users sender ON sm.dikirim_oleh = sender.id
         LEFT JOIN users receiver ON sm.diterima_oleh = receiver.id
         LEFT JOIN users canceller ON sm.dibatalkan_oleh = canceller.id
         WHERE sm.tipe = 'transfer'
           AND ua.owner_id = $1 AND ut.owner_id = $1
           AND (sm.unit_asal_id = ANY($2) OR sm.unit_tujuan_id = ANY($2))
         ORDER BY sm.id DESC",
    )
    .bind(owner_id as i32)
    .bind(&unit_ids)
    .fetch_all(&state.db)
    .await;

    let rows = match rows {
        Ok(rows) => rows,
        Err(error) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<Vec<TransferStokModel>> {
                    status: "error".to_string(),
                    message: format!("Gagal mengambil transfer stok: {error}"),
                    data: None,
                }),
            )
                .into_response()
        }
    };
    let hasil: Vec<TransferStokModel> = rows
        .into_iter()
        .map(|r| TransferStokModel {
            id: r.id as i64,
            owner_id,
            unit_asal_id: r.unit_asal_id as i64,
            nama_unit_asal: r.nama_unit_asal,
            unit_tujuan_id: r.unit_tujuan_id as i64,
            nama_unit_tujuan: r.nama_unit_tujuan,
            produk_id: r.produk_id as i64,
            nama_produk: r.nama_produk,
            jumlah: r.jumlah,
            waktu_kirim: r.tanggal.format("%Y-%m-%d %H:%M").to_string(),
            waktu_terima: r
                .waktu_terima
                .map(|t| t.format("%Y-%m-%d %H:%M").to_string()),
            pemohon: r.pemohon,
            disetujui_oleh: r.disetujui_oleh,
            waktu_persetujuan: r
                .waktu_persetujuan
                .map(|t| t.format("%Y-%m-%d %H:%M").to_string()),
            dikirim_oleh: r.dikirim_oleh,
            waktu_pengiriman: r
                .waktu_pengiriman
                .map(|t| t.format("%Y-%m-%d %H:%M").to_string()),
            diterima_oleh: r.diterima_oleh,
            alasan_penolakan: r.alasan_penolakan,
            dibatalkan_oleh: r.dibatalkan_oleh,
            waktu_pembatalan: r
                .waktu_pembatalan
                .map(|t| t.format("%Y-%m-%d %H:%M").to_string()),
            status: match r.status.as_str() {
                "disetujui" => StatusTransfer::Disetujui,
                "dikirim" => StatusTransfer::Dikirim,
                "diterima" => StatusTransfer::Diterima,
                "ditolak" => StatusTransfer::Ditolak,
                "dibatalkan" => StatusTransfer::Dibatalkan,
                _ => StatusTransfer::Pending,
            },
        })
        .collect();

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<TransferStokModel>> {
            status: "success".to_string(),
            message: format!(
                "Berhasil mengambil {} mutasi transfer stok dari database.",
                hasil.len()
            ),
            data: Some(hasil),
        }),
    )
        .into_response()
}

pub async fn create_transfer_stok(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Json(payload): Json<CreateTransferStokRequest>,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;
    let user_id = claims.user_id;
    if let Err(response) = ensure_roles(&claims, &["owner", "manager", "admin_gudang"]) {
        return response.into_response();
    }
    if let Err(response) = ensure_unit_access(&state, &claims, payload.unit_asal_id).await {
        return response.into_response();
    }
    if let Err(response) = ensure_unit_access(&state, &claims, payload.unit_tujuan_id).await {
        return response.into_response();
    }

    if payload.unit_asal_id == payload.unit_tujuan_id {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<TransferStokModel> {
                status: "error".to_string(),
                message: "Unit asal dan unit tujuan transfer tidak boleh sama.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    if payload.jumlah <= 0 {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<TransferStokModel> {
                status: "error".to_string(),
                message: "Jumlah transfer harus lebih besar dari 0.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    let result: Result<(i32, String, String, String), (StatusCode, String)> = async {
        let mut tx = state
            .db
            .begin()
            .await
            .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
        let source = sqlx::query_as::<_, (i32, i32, i32, String, String, String)>(
            "SELECT i.id, i.qty, i.reserved_qty, p.nama, ua.nama, ut.nama
             FROM inventories i
             JOIN products p ON p.id = i.product_id
             JOIN business_units ua ON ua.id = i.unit_id
             JOIN business_units ut ON ut.id = $4
             WHERE p.id = $1 AND p.owner_id = $2 AND ua.id = $3
               AND ua.owner_id = $2 AND ut.owner_id = $2
             FOR UPDATE OF i",
        )
        .bind(payload.produk_id as i32)
        .bind(owner_id as i32)
        .bind(payload.unit_asal_id as i32)
        .bind(payload.unit_tujuan_id as i32)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
        let Some((inventory_id, qty, reserved_qty, product_name, source_name, target_name)) =
            source
        else {
            return Err((
                StatusCode::FORBIDDEN,
                "Produk atau unit transfer tidak valid.".to_string(),
            ));
        };
        if !transfer_stock_available(qty, reserved_qty, payload.jumlah) {
            return Err((
                StatusCode::CONFLICT,
                "Stok tersedia tidak mencukupi.".to_string(),
            ));
        }
        let duplicate: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM stock_movements
             WHERE inventory_id = $1 AND unit_tujuan_id = $2 AND qty = $3
               AND tipe = 'transfer' AND status IN ('pending', 'disetujui', 'dikirim'))",
        )
        .bind(inventory_id)
        .bind(payload.unit_tujuan_id as i32)
        .bind(payload.jumlah)
        .fetch_one(&mut *tx)
        .await
        .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
        if duplicate {
            return Err((
                StatusCode::CONFLICT,
                "Permintaan transfer identik masih diproses.".to_string(),
            ));
        }

        let movement_id: i32 = sqlx::query_scalar(
            "INSERT INTO stock_movements
             (inventory_id, tipe, qty, tanggal, unit_asal_id, unit_tujuan_id,
              dicatat_oleh, diminta_oleh, status, created_at)
             VALUES ($1, 'transfer', $2, now(), $3, $4, $5, $5, 'pending', now())
             RETURNING id",
        )
        .bind(inventory_id)
        .bind(payload.jumlah)
        .bind(payload.unit_asal_id as i32)
        .bind(payload.unit_tujuan_id as i32)
        .bind(user_id as i32)
        .fetch_one(&mut *tx)
        .await
        .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
        sqlx::query(
            "INSERT INTO audit_logs (owner_id, aktor, role, aksi, modul, target, detail)
             VALUES ($1, $2, $3, 'Mengajukan transfer stok', 'Gudang', $4, $5)",
        )
        .bind(owner_id as i32)
        .bind(&claims.sub)
        .bind(&claims.role)
        .bind(format!("Transfer #{movement_id}"))
        .bind(format!(
            "{} unit {} dari {} ke {}",
            payload.jumlah, product_name, source_name, target_name
        ))
        .execute(&mut *tx)
        .await
        .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
        tx.commit()
            .await
            .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
        Ok((movement_id, product_name, source_name, target_name))
    }
    .await;

    match result {
        Ok((id, product, source, target)) => (
            StatusCode::CREATED,
            Json(ApiResponse::<TransferStokModel> {
                status: "success".to_string(),
                message: "Transfer tercatat dengan status pending; stok belum berubah.".to_string(),
                data: Some(TransferStokModel {
                    id: id as i64,
                    owner_id,
                    unit_asal_id: payload.unit_asal_id,
                    nama_unit_asal: source,
                    unit_tujuan_id: payload.unit_tujuan_id,
                    nama_unit_tujuan: target,
                    produk_id: payload.produk_id,
                    nama_produk: product,
                    jumlah: payload.jumlah,
                    waktu_kirim: Local::now().format("%Y-%m-%d %H:%M").to_string(),
                    waktu_terima: None,
                    pemohon: Some(claims.sub),
                    disetujui_oleh: None,
                    waktu_persetujuan: None,
                    dikirim_oleh: None,
                    waktu_pengiriman: None,
                    diterima_oleh: None,
                    alasan_penolakan: None,
                    dibatalkan_oleh: None,
                    waktu_pembatalan: None,
                    status: StatusTransfer::Pending,
                }),
            }),
        )
            .into_response(),
        Err((status, message)) => (
            status,
            Json(ApiResponse::<TransferStokModel> {
                status: "error".to_string(),
                message,
                data: None,
            }),
        )
            .into_response(),
    }
}

pub async fn update_status_transfer(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateStatusTransferRequest>,
) -> impl IntoResponse {
    if !transfer_role_allowed(&claims.role) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Role tidak berwenang memproses transfer stok.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    let next_status = match &payload.status {
        StatusTransfer::Disetujui => "disetujui",
        StatusTransfer::Ditolak => "ditolak",
        StatusTransfer::Dikirim => "dikirim",
        StatusTransfer::Diterima => "diterima",
        StatusTransfer::Dibatalkan => "dibatalkan",
        StatusTransfer::Pending => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<()> {
                    status: "error".to_string(),
                    message: "Status pending tidak dapat ditetapkan melalui endpoint transisi."
                        .to_string(),
                    data: None,
                }),
            )
                .into_response();
        }
    };
    if next_status == "ditolak" && payload.alasan.as_deref().unwrap_or("").trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Alasan penolakan wajib diisi.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    let result: Result<(), (StatusCode, String)> = async {
        let mut tx = state
            .db
            .begin()
            .await
            .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
        let row = sqlx::query_as::<_, (i32, i32, i32, i32, String)>(
            "SELECT sm.inventory_id, sm.unit_asal_id, sm.unit_tujuan_id, sm.qty, sm.status
             FROM stock_movements sm
             JOIN business_units ua ON ua.id = sm.unit_asal_id
             JOIN business_units ut ON ut.id = sm.unit_tujuan_id
             WHERE sm.id = $1 AND sm.tipe = 'transfer'
               AND ua.owner_id = $2 AND ut.owner_id = $2
             FOR UPDATE OF sm",
        )
        .bind(id as i32)
        .bind(claims.owner_id as i32)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
        let Some((inventory_id, source_id, target_id, qty, current_status)) = row else {
            return Err((StatusCode::NOT_FOUND, "Transfer tidak ditemukan.".to_string()));
        };
        let required_units: &[i32] = match next_status {
            "disetujui" | "ditolak" | "dibatalkan" => &[source_id, target_id],
            "dikirim" => &[source_id],
            "diterima" => &[target_id],
            _ => unreachable!(),
        };
        for unit_id in required_units {
            if let Err(response) = ensure_unit_access(&state, &claims, *unit_id as i64).await {
                return Err((response.status(), "Akses unit untuk memproses transfer ditolak.".to_string()));
            }
        }
        if !valid_transfer_transition(&current_status, next_status) {
            return Err((
                StatusCode::CONFLICT,
                format!("Transisi transfer dari {current_status} ke {next_status} tidak valid."),
            ));
        }

        match next_status {
            "disetujui" => {
                let updated = sqlx::query(
                    "UPDATE inventories SET reserved_qty = reserved_qty + $1
                     WHERE id = $2 AND qty - reserved_qty >= $1",
                )
                .bind(qty)
                .bind(inventory_id)
                .execute(&mut *tx)
                .await
                .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
                if updated.rows_affected() != 1 {
                    return Err((StatusCode::CONFLICT, "Stok tersedia tidak mencukupi untuk reservasi.".to_string()));
                }
                sqlx::query("UPDATE stock_movements SET status = 'disetujui', disetujui_oleh = $1, waktu_persetujuan = now() WHERE id = $2")
                    .bind(claims.user_id as i32).bind(id as i32).execute(&mut *tx).await
                    .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
            }
            "dikirim" => {
                let updated = sqlx::query(
                    "UPDATE inventories SET qty = qty - $1, reserved_qty = reserved_qty - $1
                     WHERE id = $2 AND qty >= $1 AND reserved_qty >= $1",
                )
                .bind(qty)
                .bind(inventory_id)
                .execute(&mut *tx)
                .await
                .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
                if updated.rows_affected() != 1 {
                    return Err((StatusCode::CONFLICT, "Stok sumber tidak konsisten dengan reservasi.".to_string()));
                }
                sqlx::query("UPDATE stock_movements SET status = 'dikirim', dikirim_oleh = $1, waktu_pengiriman = now() WHERE id = $2")
                    .bind(claims.user_id as i32).bind(id as i32).execute(&mut *tx).await
                    .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
            }
            "diterima" => {
                sqlx::query(
                    "INSERT INTO inventories (unit_id, product_id, qty, min_stock)
                     SELECT $1, product_id, $2, min_stock FROM inventories WHERE id = $3
                     ON CONFLICT (unit_id, product_id) DO UPDATE SET qty = inventories.qty + EXCLUDED.qty",
                )
                .bind(target_id)
                .bind(qty)
                .bind(inventory_id)
                .execute(&mut *tx)
                .await
                .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
                sqlx::query("UPDATE stock_movements SET status = 'diterima', waktu_terima = now(), diterima_oleh = $1 WHERE id = $2")
                    .bind(claims.user_id as i32).bind(id as i32).execute(&mut *tx).await
                    .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
            }
            "ditolak" | "dibatalkan" => {
                if current_status == "disetujui" {
                    let updated = sqlx::query(
                        "UPDATE inventories SET reserved_qty = reserved_qty - $1
                         WHERE id = $2 AND reserved_qty >= $1",
                    )
                    .bind(qty)
                    .bind(inventory_id)
                    .execute(&mut *tx)
                    .await
                    .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
                    if updated.rows_affected() != 1 {
                        return Err((StatusCode::CONFLICT, "Reservasi stok tidak konsisten.".to_string()));
                    }
                }
                if next_status == "ditolak" {
                    sqlx::query("UPDATE stock_movements SET status = 'ditolak', ditolak_oleh = $1, waktu_penolakan = now(), alasan_penolakan = $2 WHERE id = $3")
                        .bind(claims.user_id as i32).bind(payload.alasan.as_deref()).bind(id as i32)
                        .execute(&mut *tx).await
                        .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
                } else {
                    sqlx::query("UPDATE stock_movements SET status = 'dibatalkan', dibatalkan_oleh = $1, waktu_pembatalan = now() WHERE id = $2")
                        .bind(claims.user_id as i32).bind(id as i32).execute(&mut *tx).await
                        .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
                }
            }
            _ => unreachable!(),
        }
        sqlx::query(
            "INSERT INTO audit_logs (owner_id, aktor, role, aksi, modul, target, detail)
             VALUES ($1, $2, $3, $4, 'Gudang', $5, $6)",
        )
        .bind(claims.owner_id as i32)
        .bind(&claims.sub)
        .bind(&claims.role)
        .bind(format!("Transfer {next_status}"))
        .bind(format!("Transfer #{id}"))
        .bind(payload.alasan.as_deref().unwrap_or("Perubahan status transfer"))
        .execute(&mut *tx)
        .await
        .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
        tx.commit()
            .await
            .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;
        Ok(())
    }
    .await;

    match result {
        Ok(()) => (
            StatusCode::OK,
            Json(ApiResponse::<()> {
                status: "success".to_string(),
                message: format!("Transfer #{id} berhasil diproses menjadi {next_status}."),
                data: None,
            }),
        )
            .into_response(),
        Err((status, message)) => (
            status,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message,
                data: None,
            }),
        )
            .into_response(),
    }
}

#[cfg(test)]
mod transfer_tests {
    use super::{transfer_role_allowed, transfer_stock_available, valid_transfer_transition};

    #[test]
    fn transfer_approval_and_rejection_transitions_are_valid() {
        assert!(valid_transfer_transition("pending", "disetujui"));
        assert!(valid_transfer_transition("pending", "ditolak"));
        assert!(valid_transfer_transition("disetujui", "ditolak"));
    }

    #[test]
    fn sent_transfer_can_only_be_received_once() {
        assert!(valid_transfer_transition("dikirim", "diterima"));
        assert!(!valid_transfer_transition("diterima", "diterima"));
        assert!(!valid_transfer_transition("disetujui", "diterima"));
    }

    #[test]
    fn duplicate_processing_and_invalid_transitions_are_rejected() {
        assert!(!valid_transfer_transition("disetujui", "disetujui"));
        assert!(!valid_transfer_transition("pending", "dikirim"));
        assert!(!valid_transfer_transition("ditolak", "disetujui"));
    }

    #[test]
    fn insufficient_or_invalid_stock_is_rejected() {
        assert!(transfer_stock_available(10, 4, 6));
        assert!(!transfer_stock_available(10, 5, 6));
        assert!(!transfer_stock_available(4, 5, 1));
        assert!(!transfer_stock_available(10, 0, 0));
    }

    #[test]
    fn transfer_processing_is_restricted_to_approved_roles() {
        assert!(transfer_role_allowed("owner"));
        assert!(transfer_role_allowed("manager"));
        assert!(transfer_role_allowed("admin_gudang"));
        assert!(!transfer_role_allowed("kasir"));
        assert!(!transfer_role_allowed("auditor"));
    }
}
