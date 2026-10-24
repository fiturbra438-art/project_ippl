use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use rust_decimal::prelude::ToPrimitive;
use serde::Deserialize;
use std::sync::Arc;

use crate::auth::require_claims;
use crate::models::ProdukModel;
use crate::schemas::{AdjustStokRequest, ApiResponse, CreateProdukRequest, UpdateProdukRequest};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct ProdukQuery {
    pub unit_id: Option<i64>,
}

// 1. LIST PRODUK (Membaca langsung dari tabel PostgreSQL products & inventories)
pub async fn list_produk(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Query(query): Query<ProdukQuery>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;

    let rows = if let Some(uid) = query.unit_id {
        sqlx::query_as::<_, (i32, i32, i32, String, String, rust_decimal::Decimal, rust_decimal::Decimal, i32, i32)>(
            "SELECT p.id, p.owner_id, i.unit_id, p.nama, p.sku, p.harga_beli, p.harga_jual, i.qty, i.min_stock
             FROM products p
             JOIN inventories i ON p.id = i.product_id
             WHERE p.owner_id = $1 AND i.unit_id = $2
             ORDER BY p.id ASC"
        )
        .bind(owner_id as i32)
        .bind(uid as i32)
        .fetch_all(&state.db)
        .await
    } else {
        sqlx::query_as::<_, (i32, i32, i32, String, String, rust_decimal::Decimal, rust_decimal::Decimal, i32, i32)>(
            "SELECT p.id, p.owner_id, COALESCE(i.unit_id, 1), p.nama, p.sku, p.harga_beli, p.harga_jual, COALESCE(i.qty, 0), COALESCE(i.min_stock, 5)
             FROM products p
             LEFT JOIN inventories i ON p.id = i.product_id
             WHERE p.owner_id = $1
             ORDER BY p.id ASC"
        )
        .bind(owner_id as i32)
        .fetch_all(&state.db)
        .await
    };

    let hasil: Vec<ProdukModel> = match rows {
        Ok(list) => list
            .into_iter()
            .map(|r| ProdukModel {
                id: r.0 as i64,
                owner_id: r.1 as i64,
                unit_id: r.2 as i64,
                nama: r.3,
                sku: r.4,
                harga_beli: r.5.to_f64().unwrap_or(0.0),
                harga_jual: r.6.to_f64().unwrap_or(0.0),
                stok: r.7,
                min_stok: r.8,
            })
            .collect(),
        Err(_) => Vec::new(),
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<ProdukModel>> {
            status: "success".to_string(),
            message: format!(
                "Berhasil mengambil {} produk dari database PostgreSQL.",
                hasil.len()
            ),
            data: Some(hasil),
        }),
    )
        .into_response()
}

// 2. PRODUK STOK KRITIS (Membaca langsung dari VIEW view_produk_stok_kritis)
pub async fn list_low_stock(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;

    let rows = sqlx::query_as::<_, (i32, i32, String, String, rust_decimal::Decimal, rust_decimal::Decimal, i32, i32)>(
        "SELECT v.product_id, v.unit_id, v.nama_produk, v.sku, v.harga_beli, v.harga_jual, v.stok_saat_ini, v.batas_minimum
         FROM view_produk_stok_kritis v
         JOIN business_units b ON v.unit_id = b.id
         WHERE b.owner_id = $1"
    )
    .bind(owner_id as i32)
    .fetch_all(&state.db)
    .await;

    let kritis: Vec<ProdukModel> = match rows {
        Ok(list) => list
            .into_iter()
            .map(|r| ProdukModel {
                id: r.0 as i64,
                owner_id,
                unit_id: r.1 as i64,
                nama: r.2,
                sku: r.3,
                harga_beli: r.4.to_f64().unwrap_or(0.0),
                harga_jual: r.5.to_f64().unwrap_or(0.0),
                stok: r.6,
                min_stok: r.7,
            })
            .collect(),
        Err(_) => Vec::new(),
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<ProdukModel>> {
            status: "success".to_string(),
            message: format!(
                "Terdapat {} produk dengan stok kritis (View Database).",
                kritis.len()
            ),
            data: Some(kritis),
        }),
    )
        .into_response()
}

// 3. DETAIL PRODUK
pub async fn get_produk_detail(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let row = sqlx::query_as::<_, (i32, i32, i32, String, String, rust_decimal::Decimal, rust_decimal::Decimal, i32, i32)>(
        "SELECT p.id, p.owner_id, COALESCE(i.unit_id, 1), p.nama, p.sku, p.harga_beli, p.harga_jual, COALESCE(i.qty, 0), COALESCE(i.min_stock, 5)
         FROM products p
         LEFT JOIN inventories i ON p.id = i.product_id
          WHERE p.id = $1 AND p.owner_id = $2"
    )
    .bind(id as i32)
    .bind(claims.owner_id as i32)
    .fetch_optional(&state.db)
    .await;

    match row {
        Ok(Some(r)) => (
            StatusCode::OK,
            Json(ApiResponse::<ProdukModel> {
                status: "success".to_string(),
                message: "Detail produk ditemukan.".to_string(),
                data: Some(ProdukModel {
                    id: r.0 as i64,
                    owner_id: r.1 as i64,
                    unit_id: r.2 as i64,
                    nama: r.3,
                    sku: r.4,
                    harga_beli: r.5.to_f64().unwrap_or(0.0),
                    harga_jual: r.6.to_f64().unwrap_or(0.0),
                    stok: r.7,
                    min_stok: r.8,
                }),
            }),
        )
            .into_response(),
        _ => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: "Produk tidak ditemukan di database.".to_string(),
                data: None,
            }),
        )
            .into_response(),
    }
}

// 4. TAMBAH PRODUK (Tersimpan Permanen ke PostgreSQL products & inventories)
pub async fn create_produk(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateProdukRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;
    let aktor_role = claims.role.as_str();

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
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: "Unit usaha bukan milik bisnis Anda.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    // Validasi wewenang: Kasir dilarang mengatur harga dan membuat produk baru
    if aktor_role == "kasir" {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: "Akses ditolak: Penetapan harga modal dan harga jual hanya memiliki wewenang pada Manager atau Owner.".to_string(),
                data: None,
            }),
        ).into_response();
    }

    let min_stock = payload.min_stok.unwrap_or(5);

    // 1. Insert ke PostgreSQL `products`
    let prod_row: Result<(i32,), sqlx::Error> = sqlx::query_as(
        "INSERT INTO products (owner_id, sku, nama, kategori, harga_beli, harga_jual, satuan, created_at)
         VALUES ($1, $2, $3, 'Umum', $4, $5, 'pcs', now())
         RETURNING id"
    )
    .bind(owner_id as i32)
    .bind(&payload.sku)
    .bind(&payload.nama)
    .bind(rust_decimal::Decimal::from_f64_retain(payload.harga_beli).unwrap_or_default())
    .bind(rust_decimal::Decimal::from_f64_retain(payload.harga_jual).unwrap_or_default())
    .fetch_one(&state.db)
    .await;

    let prod_id = match prod_row {
        Ok(r) => r.0,
        Err(e) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<ProdukModel> {
                    status: "error".to_string(),
                    message: format!("Gagal menyimpan produk: {}", e),
                    data: None,
                }),
            )
                .into_response();
        }
    };

    // 2. Insert ke PostgreSQL `inventories`
    let _ = sqlx::query(
        "INSERT INTO inventories (unit_id, product_id, qty, min_stock, created_at)
         VALUES ($1, $2, $3, $4, now())",
    )
    .bind(payload.unit_id as i32)
    .bind(prod_id)
    .bind(payload.stok)
    .bind(min_stock)
    .execute(&state.db)
    .await;

    let new_produk = ProdukModel {
        id: prod_id as i64,
        owner_id,
        unit_id: payload.unit_id,
        nama: payload.nama,
        sku: payload.sku,
        harga_beli: payload.harga_beli,
        harga_jual: payload.harga_jual,
        stok: payload.stok,
        min_stok: min_stock,
    };

    (
        StatusCode::CREATED,
        Json(ApiResponse::<ProdukModel> {
            status: "success".to_string(),
            message: "Produk berhasil ditambahkan dan tersimpan permanen di database PostgreSQL."
                .to_string(),
            data: Some(new_produk),
        }),
    )
        .into_response()
}

// 5. UPDATE PRODUK (PostgreSQL update)
pub async fn update_produk(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateProdukRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let aktor_role = claims.role.as_str();

    let product_valid: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM products WHERE id = $1 AND owner_id = $2)")
            .bind(id as i32)
            .bind(claims.owner_id as i32)
            .fetch_one(&state.db)
            .await
            .unwrap_or(false);
    if !product_valid {
        return (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: "Produk tidak ditemukan.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    if aktor_role == "kasir" && (payload.harga_beli.is_some() || payload.harga_jual.is_some()) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: "Akses ditolak: Kasir tidak memiliki otoritas untuk mengubah harga modal atau harga jual.".to_string(),
                data: None,
            }),
        ).into_response();
    }

    if let Some(nama) = &payload.nama {
        let _ = sqlx::query("UPDATE products SET nama = $1 WHERE id = $2 AND owner_id = $3")
            .bind(nama)
            .bind(id as i32)
            .bind(claims.owner_id as i32)
            .execute(&state.db)
            .await;
    }
    if let Some(sku) = &payload.sku {
        let _ = sqlx::query("UPDATE products SET sku = $1 WHERE id = $2 AND owner_id = $3")
            .bind(sku)
            .bind(id as i32)
            .bind(claims.owner_id as i32)
            .execute(&state.db)
            .await;
    }
    if let Some(hb) = payload.harga_beli {
        let _ = sqlx::query("UPDATE products SET harga_beli = $1 WHERE id = $2 AND owner_id = $3")
            .bind(rust_decimal::Decimal::from_f64_retain(hb).unwrap_or_default())
            .bind(id as i32)
            .bind(claims.owner_id as i32)
            .execute(&state.db)
            .await;
    }
    if let Some(hj) = payload.harga_jual {
        let _ = sqlx::query("UPDATE products SET harga_jual = $1 WHERE id = $2 AND owner_id = $3")
            .bind(rust_decimal::Decimal::from_f64_retain(hj).unwrap_or_default())
            .bind(id as i32)
            .bind(claims.owner_id as i32)
            .execute(&state.db)
            .await;
    }
    if let Some(stok) = payload.stok {
        let _ = sqlx::query("UPDATE inventories SET qty = $1 WHERE product_id = $2 AND unit_id IN (SELECT id FROM business_units WHERE owner_id = $3)").bind(stok).bind(id as i32).bind(claims.owner_id as i32).execute(&state.db).await;
    }

    (
        StatusCode::OK,
        Json(ApiResponse::<()> {
            status: "success".to_string(),
            message: "Data produk di PostgreSQL berhasil diperbarui.".to_string(),
            data: None,
        }),
    )
        .into_response()
}

// 6. PENYESUAIAN STOK CEPAT
pub async fn adjust_stok(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<AdjustStokRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    if !["owner", "manager", "admin_gudang"].contains(&claims.role.as_str()) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Role tidak boleh mengubah stok.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    let res = sqlx::query(
        "UPDATE inventories SET qty = GREATEST(0, qty + $1) WHERE product_id = $2 AND unit_id IN (SELECT id FROM business_units WHERE owner_id = $3)"
    )
    .bind(payload.penambahan)
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
                    "Stok produk #{} berhasil disesuaikan ({}) di database.",
                    id, payload.penambahan
                ),
                data: None,
            }),
        )
            .into_response(),
        Err(e) => (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: format!("Gagal update stok: {}", e),
                data: None,
            }),
        )
            .into_response(),
    }
}

// 7. HAPUS PRODUK
pub async fn delete_produk(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    if !["owner", "manager"].contains(&claims.role.as_str()) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Role tidak boleh menghapus produk.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    let _ = sqlx::query("DELETE FROM inventories WHERE product_id = $1 AND unit_id IN (SELECT id FROM business_units WHERE owner_id = $2)").bind(id as i32).bind(claims.owner_id as i32).execute(&state.db).await;
    let res = sqlx::query("DELETE FROM products WHERE id = $1 AND owner_id = $2")
        .bind(id as i32)
        .bind(claims.owner_id as i32)
        .execute(&state.db)
        .await;

    match res {
        Ok(_) => (
            StatusCode::OK,
            Json(ApiResponse::<()> {
                status: "success".to_string(),
                message: format!("Produk #{} berhasil dihapus dari database PostgreSQL.", id),
                data: None,
            }),
        )
            .into_response(),
        Err(e) => (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: format!("Gagal menghapus produk: {}", e),
                data: None,
            }),
        )
            .into_response(),
    }
}
