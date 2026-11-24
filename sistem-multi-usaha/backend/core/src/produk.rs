use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use rust_decimal::prelude::ToPrimitive;
use serde::Deserialize;
use std::sync::Arc;

use crate::auth::ensure_unit_access;
use crate::models::{Claims, ProdukModel};
use crate::schemas::{
    AdjustStokRequest, ApiResponse, CreateProdukRequest, ImportProdukError, ImportProdukRequest,
    ImportProdukResponse, UpdateProdukRequest,
};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct ProdukQuery {
    pub unit_id: Option<i64>,
}

// 1. LIST PRODUK (Membaca langsung dari tabel PostgreSQL products & inventories)
pub async fn list_produk(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Query(query): Query<ProdukQuery>,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;
    if let Some(uid) = query.unit_id {
        if let Err(response) = ensure_unit_access(&state, &claims, uid).await {
            return response.into_response();
        }
    }

    let rows = if let Some(uid) = query.unit_id {
        sqlx::query_as::<_, (i32, i32, i32, String, String, rust_decimal::Decimal, rust_decimal::Decimal, i32, i32)>(
            "SELECT p.id, p.owner_id, i.unit_id, p.nama, p.sku, p.harga_beli, p.harga_jual, i.qty, i.min_stock
             FROM products p
             JOIN inventories i ON p.id = i.product_id
             WHERE p.owner_id = $1 AND i.unit_id = $2
               AND ($3 = 'owner' OR EXISTS (SELECT 1 FROM user_units uu WHERE uu.user_id = $4 AND uu.unit_id = i.unit_id))
             ORDER BY p.id ASC"
        )
        .bind(owner_id as i32)
        .bind(uid as i32)
        .bind(&claims.role)
        .bind(claims.user_id as i32)
        .fetch_all(&state.db)
        .await
    } else {
        sqlx::query_as::<_, (i32, i32, i32, String, String, rust_decimal::Decimal, rust_decimal::Decimal, i32, i32)>(
            "SELECT DISTINCT ON (p.id) p.id, p.owner_id, COALESCE(i.unit_id, 1), p.nama, p.sku, p.harga_beli, p.harga_jual, COALESCE(i.qty, 0), COALESCE(i.min_stock, 5)
             FROM products p
             LEFT JOIN inventories i ON p.id = i.product_id
              WHERE p.owner_id = $1
                AND ($2 = 'owner' OR EXISTS (SELECT 1 FROM user_units uu WHERE uu.user_id = $3 AND uu.unit_id = i.unit_id))
              ORDER BY p.id ASC, i.unit_id ASC"
        )
        .bind(owner_id as i32)
        .bind(&claims.role)
        .bind(claims.user_id as i32)
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
    claims: Claims,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;
    let unit_ids = match crate::auth::accessible_unit_ids(&state, &claims).await {
        Ok(ids) => ids,
        Err(response) => return response.into_response(),
    };

    let rows = sqlx::query_as::<_, (i32, i32, String, String, rust_decimal::Decimal, rust_decimal::Decimal, i32, i32)>(
        "SELECT v.product_id, v.unit_id, v.nama_produk, v.sku, v.harga_beli, v.harga_jual, v.stok_saat_ini, v.batas_minimum
         FROM view_produk_stok_kritis v
         JOIN business_units b ON v.unit_id = b.id
          WHERE b.owner_id = $1 AND v.unit_id = ANY($2)"
    )
    .bind(owner_id as i32)
    .bind(&unit_ids)
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
    claims: Claims,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let row = sqlx::query_as::<_, (i32, i32, i32, String, String, rust_decimal::Decimal, rust_decimal::Decimal, i32, i32)>(
        "SELECT p.id, p.owner_id, i.unit_id, p.nama, p.sku, p.harga_beli, p.harga_jual, i.qty, i.min_stock
         FROM products p
         JOIN inventories i ON p.id = i.product_id
          WHERE p.id = $1 AND p.owner_id = $2
            AND ($3 = 'owner' OR EXISTS (SELECT 1 FROM user_units uu WHERE uu.user_id = $4 AND uu.unit_id = i.unit_id))
          ORDER BY i.unit_id ASC LIMIT 1"
    )
    .bind(id as i32)
    .bind(claims.owner_id as i32)
    .bind(&claims.role)
    .bind(claims.user_id as i32)
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
    claims: Claims,
    Json(payload): Json<CreateProdukRequest>,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;
    let aktor_role = claims.role.as_str();
    if !["owner", "manager"].contains(&aktor_role) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: "Role tidak boleh mengelola produk.".to_string(),
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

    if payload.nama.trim().is_empty() || payload.sku.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: "Nama produk dan SKU wajib diisi.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    if payload.harga_beli < 0.0 || payload.harga_jual < 0.0 || payload.stok < 0 {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: "Harga beli, harga jual, dan stok awal tidak boleh bernilai negatif."
                    .to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    let min_stock = payload.min_stok.unwrap_or(5);

    let mut tx = match state.db.begin().await {
        Ok(tx) => tx,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<ProdukModel> {
                    status: "error".to_string(),
                    message: format!("Gagal memulai transaksi: {}", e),
                    data: None,
                }),
            )
                .into_response()
        }
    };
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
.fetch_one(&mut *tx)
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

    let inventory_result = sqlx::query(
        "INSERT INTO inventories (unit_id, product_id, qty, min_stock, created_at)
         VALUES ($1, $2, $3, $4, now())",
    )
    .bind(payload.unit_id as i32)
    .bind(prod_id)
    .bind(payload.stok)
    .bind(min_stock)
    .execute(&mut *tx)
    .await;
    if let Err(e) = inventory_result {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: format!("Gagal menyimpan inventaris: {}", e),
                data: None,
            }),
        )
            .into_response();
    }
    if let Err(e) = tx.commit().await {
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: format!("Gagal menyelesaikan transaksi: {}", e),
                data: None,
            }),
        )
            .into_response();
    }

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

// 4b. IMPOR PRODUK BATCH (validasi semua baris, lalu all-or-nothing)
pub async fn import_produk(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Json(payload): Json<ImportProdukRequest>,
) -> impl IntoResponse {
    if !["owner", "manager"].contains(&claims.role.as_str()) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<ImportProdukResponse> {
                status: "error".to_string(),
                message: "Role tidak boleh mengimpor produk.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    if let Err(response) = ensure_unit_access(&state, &claims, payload.unit_id).await {
        return response.into_response();
    }
    if payload.rows.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<ImportProdukResponse> {
                status: "error".to_string(),
                message: "Tidak ada baris produk untuk diimpor.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    if payload.rows.len() > 2000 {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<ImportProdukResponse> {
                status: "error".to_string(),
                message: "Maksimal 2000 baris per impor.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    let mut errors: Vec<ImportProdukError> = Vec::new();
    let mut seen_sku = std::collections::HashSet::new();
    for (idx, row) in payload.rows.iter().enumerate() {
        let baris = idx + 1;
        let sku = row.sku.trim();
        let nama = row.nama.trim();
        let mut pesan = Vec::new();
        if sku.is_empty() {
            pesan.push("SKU wajib diisi");
        }
        if nama.is_empty() {
            pesan.push("nama wajib diisi");
        }
        if !row.harga_beli.is_finite() || row.harga_beli < 0.0 {
            pesan.push("harga_beli tidak valid");
        }
        if !row.harga_jual.is_finite() || row.harga_jual < 0.0 {
            pesan.push("harga_jual tidak valid");
        }
        if row.stok < 0 {
            pesan.push("stok tidak boleh negatif");
        }
        if row.min_stok.unwrap_or(0) < 0 {
            pesan.push("min_stok tidak boleh negatif");
        }
        if !sku.is_empty() && !seen_sku.insert(sku.to_lowercase()) {
            pesan.push("SKU duplikat di dalam file");
        }
        if !pesan.is_empty() {
            errors.push(ImportProdukError {
                baris,
                pesan: pesan.join(", "),
            });
        }
    }

    if errors.is_empty() {
        let skus: Vec<String> = payload
            .rows
            .iter()
            .map(|row| row.sku.trim().to_string())
            .collect();
        let existing: Vec<String> =
            sqlx::query_scalar("SELECT sku FROM products WHERE owner_id = $1 AND sku = ANY($2)")
                .bind(claims.owner_id as i32)
                .bind(&skus)
                .fetch_all(&state.db)
                .await
                .unwrap_or_default();
        if !existing.is_empty() {
            for (idx, row) in payload.rows.iter().enumerate() {
                if existing.iter().any(|sku| sku == row.sku.trim()) {
                    errors.push(ImportProdukError {
                        baris: idx + 1,
                        pesan: format!("SKU '{}' sudah terdaftar", row.sku.trim()),
                    });
                }
            }
        }
    }

    if !errors.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<ImportProdukResponse> {
                status: "error".to_string(),
                message: "Impor dibatalkan; tidak ada produk yang disimpan.".to_string(),
                data: Some(ImportProdukResponse {
                    berhasil: 0,
                    gagal: errors.len(),
                    produk_ids: Vec::new(),
                    errors,
                }),
            }),
        )
            .into_response();
    }

    let mut tx = match state.db.begin().await {
        Ok(tx) => tx,
        Err(error) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<ImportProdukResponse> {
                    status: "error".to_string(),
                    message: format!("Gagal memulai transaksi impor: {error}"),
                    data: None,
                }),
            )
                .into_response()
        }
    };

    let mut produk_ids = Vec::with_capacity(payload.rows.len());
    for row in &payload.rows {
        let min_stok = row.min_stok.unwrap_or(5);
        let inserted: Result<(i32,), sqlx::Error> = sqlx::query_as(
            "INSERT INTO products (owner_id, sku, nama, kategori, harga_beli, harga_jual, satuan, created_at)
             VALUES ($1, $2, $3, 'Umum', $4, $5, 'pcs', now())
             RETURNING id",
        )
        .bind(claims.owner_id as i32)
        .bind(row.sku.trim())
        .bind(row.nama.trim())
        .bind(rust_decimal::Decimal::from_f64_retain(row.harga_beli).unwrap_or_default())
        .bind(rust_decimal::Decimal::from_f64_retain(row.harga_jual).unwrap_or_default())
        .fetch_one(&mut *tx)
        .await;
        let prod_id = match inserted {
            Ok((id,)) => id,
            Err(error) => {
                let _ = tx.rollback().await;
                return (
                    StatusCode::BAD_REQUEST,
                    Json(ApiResponse::<ImportProdukResponse> {
                        status: "error".to_string(),
                        message: format!("Impor dibatalkan: {error}"),
                        data: None,
                    }),
                )
                    .into_response();
            }
        };
        if let Err(error) = sqlx::query(
            "INSERT INTO inventories (unit_id, product_id, qty, min_stock, created_at)
             VALUES ($1, $2, $3, $4, now())",
        )
        .bind(payload.unit_id as i32)
        .bind(prod_id)
        .bind(row.stok)
        .bind(min_stok)
        .execute(&mut *tx)
        .await
        {
            let _ = tx.rollback().await;
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<ImportProdukResponse> {
                    status: "error".to_string(),
                    message: format!("Impor dibatalkan saat menyimpan stok: {error}"),
                    data: None,
                }),
            )
                .into_response();
        }
        produk_ids.push(prod_id as i64);
    }

    if let Err(error) = tx.commit().await {
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<ImportProdukResponse> {
                status: "error".to_string(),
                message: format!("Gagal menyelesaikan impor: {error}"),
                data: None,
            }),
        )
            .into_response();
    }

    let jumlah = produk_ids.len();
    (
        StatusCode::CREATED,
        Json(ApiResponse::<ImportProdukResponse> {
            status: "success".to_string(),
            message: format!("{jumlah} produk berhasil diimpor."),
            data: Some(ImportProdukResponse {
                berhasil: jumlah,
                gagal: 0,
                produk_ids,
                errors: Vec::new(),
            }),
        }),
    )
        .into_response()
}

// 5. UPDATE PRODUK (PostgreSQL update)
pub async fn update_produk(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateProdukRequest>,
) -> impl IntoResponse {
    if !["owner", "manager"].contains(&claims.role.as_str()) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: "Role tidak boleh mengelola produk.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    if payload
        .nama
        .as_ref()
        .is_some_and(|value| value.trim().is_empty())
        || payload
            .sku
            .as_ref()
            .is_some_and(|value| value.trim().is_empty())
        || payload
            .harga_beli
            .is_some_and(|value| !value.is_finite() || value < 0.0)
        || payload
            .harga_jual
            .is_some_and(|value| !value.is_finite() || value < 0.0)
        || payload.stok.is_some_and(|value| value < 0)
        || payload.min_stok.is_some_and(|value| value < 0)
    {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: "Data produk tidak valid.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    let product_valid: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM products p JOIN inventories i ON i.product_id = p.id WHERE p.id = $1 AND p.owner_id = $2 AND ($3 = 'owner' OR EXISTS (SELECT 1 FROM user_units uu WHERE uu.user_id = $4 AND uu.unit_id = i.unit_id)))",
    )
    .bind(id as i32).bind(claims.owner_id as i32).bind(&claims.role).bind(claims.user_id as i32)
    .fetch_one(&state.db).await.unwrap_or(false);
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
    let mut tx = match state.db.begin().await {
        Ok(tx) => tx,
        Err(error) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<ProdukModel> {
                    status: "error".to_string(),
                    message: format!("Gagal memulai update: {error}"),
                    data: None,
                }),
            )
                .into_response()
        }
    };
    if let Some(value) = &payload.nama {
        let result = sqlx::query("UPDATE products SET nama = $1 WHERE id = $2 AND owner_id = $3")
            .bind(value.trim())
            .bind(id as i32)
            .bind(claims.owner_id as i32)
            .execute(&mut *tx)
            .await;
        if let Err(error) = result {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<ProdukModel> {
                    status: "error".to_string(),
                    message: format!("Gagal memperbarui nama: {error}"),
                    data: None,
                }),
            )
                .into_response();
        }
    }
    if let Some(value) = &payload.sku {
        let result = sqlx::query("UPDATE products SET sku = $1 WHERE id = $2 AND owner_id = $3")
            .bind(value.trim())
            .bind(id as i32)
            .bind(claims.owner_id as i32)
            .execute(&mut *tx)
            .await;
        if let Err(error) = result {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<ProdukModel> {
                    status: "error".to_string(),
                    message: format!("Gagal memperbarui SKU: {error}"),
                    data: None,
                }),
            )
                .into_response();
        }
    }
    if let Some(value) = payload.harga_beli {
        let result =
            sqlx::query("UPDATE products SET harga_beli = $1 WHERE id = $2 AND owner_id = $3")
                .bind(rust_decimal::Decimal::from_f64_retain(value).unwrap_or_default())
                .bind(id as i32)
                .bind(claims.owner_id as i32)
                .execute(&mut *tx)
                .await;
        if let Err(error) = result {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<ProdukModel> {
                    status: "error".to_string(),
                    message: format!("Gagal memperbarui harga beli: {error}"),
                    data: None,
                }),
            )
                .into_response();
        }
    }
    if let Some(value) = payload.harga_jual {
        let result =
            sqlx::query("UPDATE products SET harga_jual = $1 WHERE id = $2 AND owner_id = $3")
                .bind(rust_decimal::Decimal::from_f64_retain(value).unwrap_or_default())
                .bind(id as i32)
                .bind(claims.owner_id as i32)
                .execute(&mut *tx)
                .await;
        if let Err(error) = result {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<ProdukModel> {
                    status: "error".to_string(),
                    message: format!("Gagal memperbarui harga jual: {error}"),
                    data: None,
                }),
            )
                .into_response();
        }
    }
    if let Some(value) = payload.stok {
        let result = sqlx::query("UPDATE inventories SET qty = $1 WHERE product_id = $2 AND unit_id IN (SELECT id FROM business_units WHERE owner_id = $3) AND $1 >= reserved_qty").bind(value).bind(id as i32).bind(claims.owner_id as i32).execute(&mut *tx).await;
        if let Err(error) = result {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<ProdukModel> {
                    status: "error".to_string(),
                    message: format!("Gagal memperbarui stok: {error}"),
                    data: None,
                }),
            )
                .into_response();
        }
    }
    if let Some(value) = payload.min_stok {
        let result = sqlx::query("UPDATE inventories SET min_stock = $1 WHERE product_id = $2 AND unit_id IN (SELECT id FROM business_units WHERE owner_id = $3)").bind(value).bind(id as i32).bind(claims.owner_id as i32).execute(&mut *tx).await;
        if let Err(error) = result {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<ProdukModel> {
                    status: "error".to_string(),
                    message: format!("Gagal memperbarui batas stok: {error}"),
                    data: None,
                }),
            )
                .into_response();
        }
    }
    if let Err(error) = tx.commit().await {
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<ProdukModel> {
                status: "error".to_string(),
                message: format!("Gagal menyimpan update produk: {error}"),
                data: None,
            }),
        )
            .into_response();
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
    claims: Claims,
    Path(id): Path<i64>,
    Json(payload): Json<AdjustStokRequest>,
) -> impl IntoResponse {
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
    if let Err(response) = ensure_unit_access(&state, &claims, payload.unit_id).await {
        return response.into_response();
    }
    let res = sqlx::query(
        "UPDATE inventories i SET qty = i.qty + $1
         FROM products p
         WHERE i.product_id = p.id AND p.id = $2 AND p.owner_id = $3
           AND i.unit_id = $4 AND i.qty + $1 >= i.reserved_qty
           AND EXISTS (SELECT 1 FROM business_units u WHERE u.id = i.unit_id AND u.owner_id = $3)",
    )
    .bind(payload.penambahan)
    .bind(id as i32)
    .bind(claims.owner_id as i32)
    .bind(payload.unit_id as i32)
    .execute(&state.db)
    .await;

    match res {
        Ok(result) if result.rows_affected() == 1 => (
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
        Ok(_) => (
            StatusCode::CONFLICT,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Stok tidak ditemukan atau pengurangan akan melanggar reservasi."
                    .to_string(),
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
    claims: Claims,
    Path(id): Path<i64>,
) -> impl IntoResponse {
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
