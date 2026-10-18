use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use serde::Deserialize;
use std::sync::Arc;
use chrono::Local;

use crate::auth::extract_claims;
use crate::models::{AuditLogModel, ProdukModel};
use crate::schemas::{AdjustStokRequest, ApiResponse, CreateProdukRequest, UpdateProdukRequest};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct ProdukQuery {
    pub unit_id: Option<i64>,
}

// 1. LIST PRODUK (Bisa difilter per unit_id)
pub async fn list_produk(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Query(query): Query<ProdukQuery>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    let produks = state.produks.read().await;

    let hasil: Vec<ProdukModel> = produks
        .iter()
        .filter(|p| {
            if p.owner_id != owner_id {
                return false;
            }
            if let Some(uid) = query.unit_id {
                if uid > 0 && p.unit_id != uid {
                    return false;
                }
            }
            true
        })
        .cloned()
        .collect();

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<ProdukModel>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} produk.", hasil.len()),
            data: Some(hasil),
        }),
    )
}

// 2. PRODUK STOK KRITIS / LOW STOCK ALERTS
pub async fn list_low_stock(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    let produks = state.produks.read().await;

    let kritis: Vec<ProdukModel> = produks
        .iter()
        .filter(|p| p.owner_id == owner_id && p.stok <= p.min_stok)
        .cloned()
        .collect();

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<ProdukModel>> {
            status: "success".to_string(),
            message: format!("Terdapat {} produk dengan stok kritis.", kritis.len()),
            data: Some(kritis),
        }),
    )
}

// 3. DETAIL PRODUK
pub async fn get_produk_detail(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let produks = state.produks.read().await;

    match produks.iter().find(|p| p.id == id) {
        Some(p) => (
            StatusCode::OK,
            Json(ApiResponse::<ProdukModel> {
                status: "success".to_string(),
                message: "Detail produk ditemukan.".to_string(),
                data: Some(p.clone()),
            }),
        ),
        None => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: "Produk tidak ditemukan.".to_string(),
                data: None,
            }),
        ),
    }
}

// 4. TAMBAH PRODUK (Hanya Owner & Manager yang berhak menentukan harga modal & jual)
pub async fn create_produk(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateProdukRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);
    let aktor_nama = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "User Demo".to_string());
    let aktor_role = claims.as_ref().map(|c| c.role.clone()).unwrap_or_else(|| "manager".to_string());

    // Validasi wewenang: Kasir dilarang mengatur harga dan membuat produk baru
    if aktor_role == "kasir" {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: "Akses ditolak: Penetapan harga modal dan harga jual hanya memiliki wewenang pada Manager atau Owner.".to_string(),
                data: None,
            }),
        );
    }

    let mut produks = state.produks.write().await;
    let new_id = (produks.len() as i64) + 1;

    let new_produk = ProdukModel {
        id: new_id,
        owner_id,
        unit_id: payload.unit_id,
        nama: payload.nama.clone(),
        sku: payload.sku,
        harga_beli: payload.harga_beli,
        harga_jual: payload.harga_jual,
        stok: payload.stok,
        min_stok: payload.min_stok.unwrap_or(5),
    };

    produks.push(new_produk.clone());
    drop(produks);

    // Audit Log
    let mut logs = state.audit_logs.write().await;
    let log_id = (logs.len() as i64) + 1;
    logs.push(AuditLogModel {
        id: log_id,
        owner_id,
        aktor: aktor_nama,
        role: aktor_role,
        aksi: "Tambah Produk".to_string(),
        modul: "Inventaris".to_string(),
        target: payload.nama,
        detail: format!("Menambahkan produk baru ID #{} untuk unit #{}", new_id, payload.unit_id),
        waktu: Local::now().format("%Y-%m-%d %H:%M").to_string(),
    });

    (
        StatusCode::CREATED,
        Json(ApiResponse::<ProdukModel> {
            status: "success".to_string(),
            message: "Produk berhasil ditambahkan ke katalog.".to_string(),
            data: Some(new_produk),
        }),
    )
}

// 5. UPDATE PRODUK (Hanya Owner & Manager yang berhak mengubah harga)
pub async fn update_produk(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateProdukRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let aktor_role = claims.as_ref().map(|c| c.role.clone()).unwrap_or_else(|| "manager".to_string());

    // Validasi jika kasir mencoba mengubah harga
    if aktor_role == "kasir" && (payload.harga_beli.is_some() || payload.harga_jual.is_some()) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: "Akses ditolak: Kasir tidak memiliki otoritas untuk mengubah harga modal atau harga jual.".to_string(),
                data: None,
            }),
        );
    }

    let mut produks = state.produks.write().await;

    if let Some(p) = produks.iter_mut().find(|p| p.id == id) {
        if let Some(nama) = payload.nama {
            p.nama = nama;
        }
        if let Some(sku) = payload.sku {
            p.sku = sku;
        }
        if let Some(hb) = payload.harga_beli {
            p.harga_beli = hb;
        }
        if let Some(hj) = payload.harga_jual {
            p.harga_jual = hj;
        }
        if let Some(stok) = payload.stok {
            p.stok = stok;
        }
        if let Some(min) = payload.min_stok {
            p.min_stok = min;
        }

        return (
            StatusCode::OK,
            Json(ApiResponse::<ProdukModel> {
                status: "success".to_string(),
                message: "Data produk berhasil diperbarui.".to_string(),
                data: Some(p.clone()),
            }),
        );
    }

    (
        StatusCode::NOT_FOUND,
        Json(ApiResponse::<ProdukModel> {
            status: "error".to_string(),
            message: "Produk tidak ditemukan.".to_string(),
            data: None,
        }),
    )
}

// 6. PENYESUAIAN STOK CEPAT
pub async fn adjust_stok(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i64>,
    Json(payload): Json<AdjustStokRequest>,
) -> impl IntoResponse {
    let mut produks = state.produks.write().await;

    if let Some(p) = produks.iter_mut().find(|p| p.id == id) {
        let stok_lama = p.stok;
        p.stok = (p.stok + payload.penambahan).max(0);

        return (
            StatusCode::OK,
            Json(ApiResponse::<ProdukModel> {
                status: "success".to_string(),
                message: format!(
                    "Stok produk {} disesuaikan: {} -> {} (perubahan: {})",
                    p.nama, stok_lama, p.stok, payload.penambahan
                ),
                data: Some(p.clone()),
            }),
        );
    }

    (
        StatusCode::NOT_FOUND,
        Json(ApiResponse::<ProdukModel> {
            status: "error".to_string(),
            message: "Produk tidak ditemukan.".to_string(),
            data: None,
        }),
    )
}

// 7. HAPUS PRODUK
pub async fn delete_produk(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let mut produks = state.produks.write().await;
    let initial_len = produks.len();
    produks.retain(|p| p.id != id);

    if produks.len() < initial_len {
        (
            StatusCode::OK,
            Json(ApiResponse::<()> {
                status: "success".to_string(),
                message: format!("Produk #{} berhasil dihapus.", id),
                data: None,
            }),
        )
    } else {
        (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Produk tidak ditemukan.".to_string(),
                data: None,
            }),
        )
    }
}
