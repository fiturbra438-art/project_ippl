use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use chrono::Local;
use serde::Deserialize;
use std::sync::Arc;

use crate::auth::{accessible_unit_ids, ensure_unit_access};
use crate::models::{
    Claims, JenisTransaksi, RefundItemModel, RefundModel, RentalServiceOrderModel, ShiftKasirModel,
    StatusShift, TransaksiDetailModel, TransaksiItemDetailModel, TransaksiModel,
};
use crate::schemas::{
    ApiResponse, BukaShiftRequest, CheckoutRequest, CreateTransaksiManualRequest,
    RefundTransaksiRequest, ReturnRentalRequest, TutupShiftRequest, UpdateServiceStatusRequest,
};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct TransaksiQuery {
    pub unit_id: Option<i64>,
    pub jenis: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

pub(crate) fn bulatkan_dua(nilai: f64) -> f64 {
    (nilai * 100.0).round() / 100.0
}

pub(crate) fn hitung_nilai_refund(
    subtotal: f64,
    qty_awal: i32,
    qty_refund: i32,
    faktor_diskon: f64,
) -> f64 {
    if qty_awal <= 0 || qty_refund <= 0 || subtotal <= 0.0 {
        return 0.0;
    }
    let dasar = subtotal * (qty_refund as f64) / (qty_awal as f64);
    bulatkan_dua((dasar * faktor_diskon).max(0.0))
}

pub(crate) fn refund_masih_boleh(total: f64, sudah: f64, baru: f64) -> bool {
    if baru <= 0.0 {
        return false;
    }
    (sudah + baru) <= total + 0.01
}

// 1. STATUS SHIFT KASIR AKTIF (Membaca langsung dari tabel PostgreSQL cashier_shifts)
pub async fn get_shift_status(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Path(unit_id): Path<i64>,
) -> impl IntoResponse {
    use rust_decimal::prelude::ToPrimitive;

    if let Err(err) = ensure_unit_access(&state, &claims, unit_id).await {
        return err;
    }

    // Pastikan unit usaha yang diminta memang milik tenant pengguna.
    let unit_valid: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM business_units WHERE id = $1 AND owner_id = $2)",
    )
    .bind(unit_id as i32)
    .bind(claims.owner_id as i32)
    .fetch_one(&state.db)
    .await
    .unwrap_or(false);

    if !unit_valid {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<Option<ShiftKasirModel>> {
                status: "error".to_string(),
                message: "Unit usaha tidak valid atau bukan milik bisnis Anda.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    let shift_row = sqlx::query_as::<
        _,
        (
            i32,
            i32,
            i32,
            String,
            rust_decimal::Decimal,
            rust_decimal::Decimal,
            rust_decimal::Decimal,
            i32,
            chrono::NaiveDateTime,
            Option<chrono::NaiveDateTime>,
            String,
        ),
    >(
        "SELECT id, unit_id, kasir_id, nama_kasir, modal_awal, total_penjualan_tunai, total_penjualan_non_tunai, total_transaksi, waktu_buka, waktu_tutup, status
         FROM cashier_shifts
         WHERE unit_id = $1 AND status = 'open'
         ORDER BY id DESC LIMIT 1",
    )
    .bind(unit_id as i32)
    .fetch_optional(&state.db)
    .await;

    let active_shift = match shift_row {
        Ok(Some(r)) => Some(ShiftKasirModel {
            id: r.0 as i64,
            unit_id: r.1 as i64,
            kasir_id: r.2 as i64,
            nama_kasir: r.3,
            modal_awal: r.4.to_f64().unwrap_or(0.0),
            total_penjualan_tunai: r.5.to_f64().unwrap_or(0.0),
            total_penjualan_non_tunai: r.6.to_f64().unwrap_or(0.0),
            total_transaksi: r.7,
            waktu_buka: r.8.format("%Y-%m-%d %H:%M").to_string(),
            waktu_tutup: r.9.map(|t| t.format("%Y-%m-%d %H:%M").to_string()),
            status: StatusShift::Open,
        }),
        _ => None,
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<Option<ShiftKasirModel>> {
            status: "success".to_string(),
            message: if active_shift.is_some() {
                "Shift kasir aktif ditemukan.".to_string()
            } else {
                "Tidak ada shift kasir yang sedang buka.".to_string()
            },
            data: Some(active_shift),
        }),
    )
        .into_response()
}

// 2. BUKA SHIFT KASIR (Memanggil Stored Procedure: CALL sp_buka_shift_kasir)
pub async fn buka_shift(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Json(payload): Json<BukaShiftRequest>,
) -> impl IntoResponse {
    if !["owner", "manager", "kasir"].contains(&claims.role.as_str()) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<ShiftKasirModel> {
                status: "error".to_string(),
                message: "Role Anda tidak berwenang membuka shift kasir.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    if let Err(err) = ensure_unit_access(&state, &claims, payload.unit_id).await {
        return err;
    }

    // Pastikan unit usaha target milik tenant pengguna (mencegah buka shift lintas tenant).
    let unit_valid: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM business_units WHERE id = $1 AND owner_id = $2)",
    )
    .bind(payload.unit_id as i32)
    .bind(claims.owner_id as i32)
    .fetch_one(&state.db)
    .await
    .unwrap_or(false);

    if !unit_valid {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<ShiftKasirModel> {
                status: "error".to_string(),
                message: "Unit usaha tidak valid atau bukan milik bisnis Anda.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    if payload.modal_awal < 0.0 {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<ShiftKasirModel> {
                status: "error".to_string(),
                message: "Modal awal tidak boleh negatif.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    let kasir_id = claims.user_id;
    let kasir_nama = claims.sub.clone();

    let result: Result<(Option<i32>, Option<String>, Option<String>), sqlx::Error> =
        sqlx::query_as("CALL sp_buka_shift_kasir($1, $2, $3, $4, NULL, NULL, NULL)")
            .bind(payload.unit_id as i32)
            .bind(kasir_id as i32)
            .bind(&kasir_nama)
            .bind(rust_decimal::Decimal::from_f64_retain(payload.modal_awal).unwrap_or_default())
            .fetch_one(&state.db)
            .await;

    match result {
        Ok((shift_id_opt, status_opt, pesan_opt)) => {
            let status_str = status_opt.unwrap_or_else(|| "error".to_string());
            let pesan_str = pesan_opt.unwrap_or_else(|| "Gagal membuka shift.".to_string());

            if status_str == "error" {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(ApiResponse::<ShiftKasirModel> {
                        status: "error".to_string(),
                        message: pesan_str,
                        data: None,
                    }),
                )
                    .into_response();
            }

            let shift_id = shift_id_opt.unwrap_or(0) as i64;
            let waktu_now = Local::now().format("%Y-%m-%d %H:%M").to_string();

            let new_shift = ShiftKasirModel {
                id: shift_id,
                unit_id: payload.unit_id,
                kasir_id,
                nama_kasir: kasir_nama,
                modal_awal: payload.modal_awal,
                total_penjualan_tunai: 0.0,
                total_penjualan_non_tunai: 0.0,
                total_transaksi: 0,
                waktu_buka: waktu_now,
                waktu_tutup: None,
                status: StatusShift::Open,
            };

            (
                StatusCode::CREATED,
                Json(ApiResponse::<ShiftKasirModel> {
                    status: "success".to_string(),
                    message: pesan_str,
                    data: Some(new_shift),
                }),
            )
                .into_response()
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<ShiftKasirModel> {
                status: "error".to_string(),
                message: format!("Error database: {}", e),
                data: None,
            }),
        )
            .into_response(),
    }
}

// 3. TUTUP SHIFT KASIR (Memanggil Stored Procedure: CALL sp_tutup_shift_kasir)
pub async fn tutup_shift(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Json(payload): Json<TutupShiftRequest>,
) -> impl IntoResponse {
    if let Err(response) = crate::auth::ensure_roles(&claims, &["owner", "manager", "kasir"]) {
        return response.into_response();
    }
    let shift_unit: Option<i64> = sqlx::query_scalar(
        "SELECT s.unit_id::bigint FROM cashier_shifts s JOIN business_units u ON u.id = s.unit_id WHERE s.id = $1 AND u.owner_id = $2"
    )
    .bind(payload.shift_id as i32)
    .bind(claims.owner_id as i32)
    .fetch_optional(&state.db)
    .await
    .unwrap_or(None);
    let shift_valid = shift_unit.is_some();
    if let Some(unit_id) = shift_unit {
        if let Err(err) = ensure_unit_access(&state, &claims, unit_id).await {
            return err;
        }
    }
    if !shift_valid {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<ShiftKasirModel> {
                status: "error".to_string(),
                message: "Shift tidak ditemukan atau bukan milik bisnis Anda.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    let result: Result<
        (
            Option<rust_decimal::Decimal>,
            Option<String>,
            Option<String>,
        ),
        sqlx::Error,
    > = sqlx::query_as("CALL sp_tutup_shift_kasir($1, $2, NULL, NULL, NULL)")
        .bind(payload.shift_id as i32)
        .bind(
            rust_decimal::Decimal::from_f64_retain(payload.uang_fisik_laci.unwrap_or(0.0))
                .unwrap_or_default(),
        )
        .fetch_one(&state.db)
        .await;

    match result {
        Ok((_selisih_opt, status_opt, pesan_opt)) => {
            let status_str = status_opt.unwrap_or_else(|| "error".to_string());
            let pesan_str = pesan_opt.unwrap_or_else(|| "Gagal menutup shift.".to_string());

            if status_str == "error" {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(ApiResponse::<ShiftKasirModel> {
                        status: "error".to_string(),
                        message: pesan_str,
                        data: None,
                    }),
                )
                    .into_response();
            }

            let waktu_tutup = Local::now().format("%Y-%m-%d %H:%M").to_string();
            let shift_hasil = ShiftKasirModel {
                id: payload.shift_id,
                unit_id: 0,
                kasir_id: claims.user_id,
                nama_kasir: claims.sub.clone(),
                modal_awal: 0.0,
                total_penjualan_tunai: 0.0,
                total_penjualan_non_tunai: 0.0,
                total_transaksi: 0,
                waktu_buka: waktu_tutup.clone(),
                waktu_tutup: Some(waktu_tutup),
                status: StatusShift::Closed,
            };

            (
                StatusCode::OK,
                Json(ApiResponse::<ShiftKasirModel> {
                    status: "success".to_string(),
                    message: pesan_str,
                    data: Some(shift_hasil),
                }),
            )
                .into_response()
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<ShiftKasirModel> {
                status: "error".to_string(),
                message: format!("Error database: {}", e),
                data: None,
            }),
        )
            .into_response(),
    }
}

// 4. CHECKOUT TRANSAKSI KASIR
// Dijalankan dengan memanggil Stored Procedure PostgreSQL: "CALL sp_proses_checkout_kasir(...)"
// Prosedur ini otomatis memicu Trigger pemotongan stok, trigger update omzet, validasi Function stok, dan pencatatan audit.
pub async fn checkout_pos(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Json(payload): Json<CheckoutRequest>,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;
    let user_id = claims.user_id;
    let _kasir_nama = claims.sub.clone();

    if let Err(err) = ensure_unit_access(&state, &claims, payload.unit_id).await {
        return err;
    }

    // Verifikasi bahwa unit_id milik owner_id terkait
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
            Json(ApiResponse::<TransaksiModel> {
                status: "error".to_string(),
                message: "Unit usaha tidak valid atau bukan milik bisnis Anda.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    if payload.items.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<TransaksiModel> {
                status: "error".to_string(),
                message: "Keranjang belanja tidak boleh kosong.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    // Siapkan items dalam format JSONB untuk dikirim ke Stored Procedure
    // Mendukung algoritma kasir fleksibel: Toko Retail, Rental/Penyewaan, Jasa & Servis, serta Item Bebas/Ad-hoc
    let mut mapped_items: Vec<serde_json::Value> = Vec::new();
    for it in &payload.items {
        if it.jumlah <= 0 {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<TransaksiModel> {
                    status: "error".to_string(),
                    message: "Jumlah produk harus lebih besar dari nol.".to_string(),
                    data: None,
                }),
            )
                .into_response();
        }

        let tipe_item = it
            .tipe
            .clone()
            .unwrap_or_else(|| "barang".to_string())
            .to_lowercase();
        if !["barang", "rental", "jasa"].contains(&tipe_item.as_str()) {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<TransaksiModel> {
                    status: "error".to_string(),
                    message: format!(
                        "Tipe item '{}' tidak valid. Pilihan: barang, rental, jasa.",
                        tipe_item
                    ),
                    data: None,
                }),
            )
                .into_response();
        }

        let prod_id_opt = it.produk_id.filter(|&id| id > 0);

        // Jika terdaftar sebagai produk fisik di master database
        let (harga_final, nama_final) = if let Some(pid) = prod_id_opt {
            let info_server: Option<(rust_decimal::Decimal, String)> = sqlx::query_as(
                "SELECT p.harga_jual, p.nama
                 FROM products p
                 JOIN inventories i ON i.product_id = p.id
                 WHERE p.id = $1 AND p.owner_id = $2 AND i.unit_id = $3",
            )
            .bind(pid as i32)
            .bind(owner_id as i32)
            .bind(payload.unit_id as i32)
            .fetch_optional(&state.db)
            .await
            .unwrap_or(None);

            match info_server {
                Some((harga_db, nama_db)) => {
                    // Harga kustom hanya dipakai bila valid (>= 0). Harga dari DB jadi acuan aman.
                    let harga_satuan = match it.harga_satuan {
                        Some(custom_h) if custom_h >= 0.0 => {
                            rust_decimal::Decimal::from_f64_retain(custom_h).unwrap_or(harga_db)
                        }
                        Some(_) => {
                            return (
                                StatusCode::BAD_REQUEST,
                                Json(ApiResponse::<TransaksiModel> {
                                    status: "error".to_string(),
                                    message: "Harga satuan tidak boleh negatif.".to_string(),
                                    data: None,
                                }),
                            )
                                .into_response();
                        }
                        None => harga_db,
                    };
                    let nama_item = it.nama.clone().unwrap_or(nama_db);
                    (harga_satuan, nama_item)
                }
                None => {
                    // Tolak produk lintas-tenant / tidak valid: jangan diam-diam
                    // memperlakukannya sebagai item kustom (mencegah injeksi produk).
                    return (
                        StatusCode::FORBIDDEN,
                        Json(ApiResponse::<TransaksiModel> {
                            status: "error".to_string(),
                            message: format!(
                                "Produk ID #{} tidak ditemukan pada unit usaha ini atau bukan milik bisnis Anda.",
                                pid
                            ),
                            data: None,
                        }),
                    )
                        .into_response();
                }
            }
        } else {
            // Item Ad-hoc / Jasa / Rental tanpa keterikatan produk inventori fisik
            let h = match it.harga_satuan {
                Some(h) if h >= 0.0 => {
                    rust_decimal::Decimal::from_f64_retain(h).unwrap_or_default()
                }
                Some(_) => {
                    return (
                        StatusCode::BAD_REQUEST,
                        Json(ApiResponse::<TransaksiModel> {
                            status: "error".to_string(),
                            message: "Harga satuan tidak boleh negatif.".to_string(),
                            data: None,
                        }),
                    )
                        .into_response();
                }
                None => rust_decimal::Decimal::ZERO,
            };
            let n = it
                .nama
                .clone()
                .unwrap_or_else(|| format!("Layanan {}", tipe_item.to_uppercase()));
            (h, n)
        };

        let diskon_item = match it.diskon {
            Some(d) if d >= 0.0 => d,
            Some(_) => {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(ApiResponse::<TransaksiModel> {
                        status: "error".to_string(),
                        message: "Diskon item tidak boleh negatif.".to_string(),
                        data: None,
                    }),
                )
                    .into_response();
            }
            None => 0.0,
        };

        mapped_items.push(serde_json::json!({
            "product_id": prod_id_opt.unwrap_or(0),
            "nama": nama_final,
            "tipe": tipe_item,
            "qty": it.jumlah,
            "harga_satuan": harga_final,
            "diskon": diskon_item,
            "durasi": it.durasi.unwrap_or(1),
            "unit_durasi": it.unit_durasi.clone().unwrap_or_else(|| "jam".to_string()),
            "catatan": it.catatan.clone().unwrap_or_default()
        }));
    }
    let items_json = serde_json::Value::Array(mapped_items);

    let diskon_nominal = match payload.diskon_nominal {
        Some(d) if d >= 0.0 => d,
        Some(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<TransaksiModel> {
                    status: "error".to_string(),
                    message: "Diskon transaksi tidak boleh negatif.".to_string(),
                    data: None,
                }),
            )
                .into_response();
        }
        None => 0.0,
    };

    // Panggil Stored Procedure tunggal di PostgreSQL:
    // Stored Procedure di dalam database otomatis memanggil:
    // - Function fn_cek_ketersediaan_stok
    // - Function fn_hitung_total_belanja
    // - Trigger trg_kurangi_stok_inventaris
    // - Trigger trg_update_omzet_unit
    let catatan_transaksi = payload.notes.clone().or_else(|| payload.keterangan.clone());
    let operation_mode = payload
        .operation_mode
        .clone()
        .unwrap_or_else(|| "fleksibel".to_string());
    let diskon_dec = rust_decimal::Decimal::from_f64_retain(diskon_nominal).unwrap_or_default();

    let result: Result<
        (
            Option<i32>,
            Option<rust_decimal::Decimal>,
            Option<String>,
            Option<String>,
        ),
        sqlx::Error,
    > = sqlx::query_as(
        "CALL sp_proses_checkout_kasir($1, $2, $3, $4, $5, $6, $7, $8, NULL, NULL, NULL, NULL)",
    )
    .bind(payload.unit_id as i32)
    .bind(user_id as i32)
    .bind(&payload.metode_pembayaran)
    .bind(items_json)
    .bind(&payload.customer_name)
    .bind(&catatan_transaksi)
    .bind(&operation_mode)
    .bind(diskon_dec)
    .fetch_one(&state.db)
    .await;

    match result {
        Ok((trx_id_opt, total_opt, status_opt, pesan_opt)) => {
            let status_str = status_opt.unwrap_or_else(|| "error".to_string());
            let pesan_str = pesan_opt.unwrap_or_else(|| "Terjadi kesalahan sistem.".to_string());

            if status_str == "error" {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(ApiResponse::<TransaksiModel> {
                        status: "error".to_string(),
                        message: pesan_str,
                        data: None,
                    }),
                )
                    .into_response();
            }

            let trx_id = trx_id_opt.unwrap_or(0) as i64;
            use rust_decimal::prelude::ToPrimitive;
            let total_belanja = total_opt.and_then(|d| d.to_f64()).unwrap_or(0.0);
            let waktu_transaksi = Local::now().format("%Y-%m-%d %H:%M").to_string();

            // Ambil nama unit usaha dari PostgreSQL
            let nama_unit: String = sqlx::query_scalar(
                "SELECT nama FROM business_units WHERE id = $1 AND owner_id = $2",
            )
            .bind(payload.unit_id as i32)
            .bind(owner_id as i32)
            .fetch_optional(&state.db)
            .await
            .ok()
            .flatten()
            .unwrap_or_else(|| "Unit Usaha".to_string());

            let new_trx = TransaksiModel {
                id: trx_id,
                owner_id,
                unit_id: payload.unit_id,
                nama_unit,
                tanggal: waktu_transaksi,
                jenis: JenisTransaksi::Pemasukan,
                kategori: "Penjualan POS".to_string(),
                jumlah: total_belanja,
                keterangan: payload.keterangan.unwrap_or_else(|| {
                    format!("Order POS #{} - {}", trx_id, payload.metode_pembayaran)
                }),
                metode_pembayaran: Some(payload.metode_pembayaran),
                items: None,
            };

            (
                StatusCode::CREATED,
                Json(ApiResponse::<TransaksiModel> {
                    status: "success".to_string(),
                    message:
                        "Transaksi berhasil diproses via Stored Procedure & Trigger PostgreSQL."
                            .to_string(),
                    data: Some(new_trx),
                }),
            )
                .into_response()
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<TransaksiModel> {
                status: "error".to_string(),
                message: format!("Gagal memanggil stored procedure database: {}", e),
                data: None,
            }),
        )
            .into_response(),
    }
}

// 5. RIWAYAT TRANSAKSI (Membaca langsung dari PostgreSQL transactions & business_units)
pub async fn list_transaksi(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Query(query): Query<TransaksiQuery>,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;

    if let Some(uid) = query.unit_id {
        if let Err(err) = ensure_unit_access(&state, &claims, uid).await {
            return err;
        }
    }
    let scoped_ids =
        if query.unit_id.is_none() && !["owner", "auditor"].contains(&claims.role.as_str()) {
            match accessible_unit_ids(&state, &claims).await {
                Ok(ids) => Some(ids),
                Err(err) => return err,
            }
        } else {
            None
        };

    // Ambil data transaksi langsung dari PostgreSQL
    let rows = if let Some(uid) = query.unit_id {
        sqlx::query_as::<
            _,
            (
                i32,
                i32,
                i32,
                String,
                chrono::NaiveDateTime,
                rust_decimal::Decimal,
                String,
                String,
            ),
        >(
            "SELECT t.id, u.owner_id, t.unit_id, u.nama AS nama_unit, t.tanggal, t.total, t.metode_bayar, t.status
             FROM transactions t
             JOIN business_units u ON u.id = t.unit_id
             WHERE u.owner_id = $1 AND t.unit_id = $2
             ORDER BY t.id DESC",
        )
        .bind(owner_id as i32)
        .bind(uid as i32)
        .fetch_all(&state.db)
        .await
    } else if let Some(ids) = &scoped_ids {
        sqlx::query_as::<
            _,
            (
                i32,
                i32,
                i32,
                String,
                chrono::NaiveDateTime,
                rust_decimal::Decimal,
                String,
                String,
            ),
        >(
            "SELECT t.id, u.owner_id, t.unit_id, u.nama AS nama_unit, t.tanggal, t.total, t.metode_bayar, t.status
             FROM transactions t
             JOIN business_units u ON u.id = t.unit_id
             WHERE u.owner_id = $1 AND t.unit_id = ANY($2)
             ORDER BY t.id DESC",
        )
        .bind(owner_id as i32)
        .bind(ids)
        .fetch_all(&state.db)
        .await
    } else {
        sqlx::query_as::<
            _,
            (
                i32,
                i32,
                i32,
                String,
                chrono::NaiveDateTime,
                rust_decimal::Decimal,
                String,
                String,
            ),
        >(
            "SELECT t.id, u.owner_id, t.unit_id, u.nama AS nama_unit, t.tanggal, t.total, t.metode_bayar, t.status
             FROM transactions t
             JOIN business_units u ON u.id = t.unit_id
             WHERE u.owner_id = $1
             ORDER BY t.id DESC",
        )
        .bind(owner_id as i32)
        .fetch_all(&state.db)
        .await
    };

    use rust_decimal::prelude::ToPrimitive;
    let mut hasil: Vec<TransaksiModel> = match rows {
        Ok(list) => list
            .into_iter()
            .map(|r| {
                let total_f64 = r.5.to_f64().unwrap_or(0.0);
                TransaksiModel {
                    id: r.0 as i64,
                    owner_id: r.1 as i64,
                    unit_id: r.2 as i64,
                    nama_unit: r.3,
                    tanggal: r.4.format("%Y-%m-%d %H:%M").to_string(),
                    jenis: JenisTransaksi::Pemasukan,
                    kategori: "Penjualan POS".to_string(),
                    jumlah: total_f64,
                    keterangan: format!("Transaksi Kasir #{} ({})", r.0, r.7),
                    metode_pembayaran: Some(r.6),
                    items: None,
                }
            })
            .collect(),
        Err(e) => {
            tracing::error!("Gagal mengambil riwayat transaksi dari PostgreSQL: {}", e);
            Vec::new()
        }
    };

    // Gabungkan dengan transaksi manual yang tersimpan permanen di tabel cash_flows
    let cash_rows = if let Some(uid) = query.unit_id {
        sqlx::query_as::<
            _,
            (
                i32,
                i32,
                String,
                chrono::NaiveDateTime,
                String,
                String,
                rust_decimal::Decimal,
            ),
        >(
            "SELECT c.id, c.unit_id, u.nama, c.tanggal::timestamp, c.jenis, c.kategori, c.jumlah
             FROM cash_flows c
             JOIN business_units u ON u.id = c.unit_id
             WHERE u.owner_id = $1 AND c.unit_id = $2
             ORDER BY c.id DESC",
        )
        .bind(owner_id as i32)
        .bind(uid as i32)
        .fetch_all(&state.db)
        .await
    } else if let Some(ids) = &scoped_ids {
        sqlx::query_as::<
            _,
            (
                i32,
                i32,
                String,
                chrono::NaiveDateTime,
                String,
                String,
                rust_decimal::Decimal,
            ),
        >(
            "SELECT c.id, c.unit_id, u.nama, c.tanggal::timestamp, c.jenis, c.kategori, c.jumlah
             FROM cash_flows c
             JOIN business_units u ON u.id = c.unit_id
             WHERE u.owner_id = $1 AND c.unit_id = ANY($2)
             ORDER BY c.id DESC",
        )
        .bind(owner_id as i32)
        .bind(ids)
        .fetch_all(&state.db)
        .await
    } else {
        sqlx::query_as::<
            _,
            (
                i32,
                i32,
                String,
                chrono::NaiveDateTime,
                String,
                String,
                rust_decimal::Decimal,
            ),
        >(
            "SELECT c.id, c.unit_id, u.nama, c.tanggal::timestamp, c.jenis, c.kategori, c.jumlah
             FROM cash_flows c
             JOIN business_units u ON u.id = c.unit_id
             WHERE u.owner_id = $1
             ORDER BY c.id DESC",
        )
        .bind(owner_id as i32)
        .fetch_all(&state.db)
        .await
    };

    if let Ok(list) = cash_rows {
        for r in list {
            let jenis = if r.4.eq_ignore_ascii_case("masuk") {
                JenisTransaksi::Pemasukan
            } else {
                JenisTransaksi::Pengeluaran
            };
            hasil.push(TransaksiModel {
                id: r.0 as i64,
                owner_id,
                unit_id: r.1 as i64,
                nama_unit: r.2,
                tanggal: r.3.format("%Y-%m-%d %H:%M").to_string(),
                jenis,
                kategori: r.5,
                jumlah: r.6.to_f64().unwrap_or(0.0),
                keterangan: "Transaksi Manual".to_string(),
                metode_pembayaran: Some("Manual".to_string()),
                items: None,
            });
        }
    }

    // Urutkan gabungan transaksi POS + manual dari yang terbaru
    hasil.sort_by(|a, b| b.tanggal.cmp(&a.tanggal));

    // Filter berdasarkan query jenis jika ada
    if let Some(j) = &query.jenis {
        let j_lower = j.to_lowercase();
        hasil.retain(|t| {
            if j_lower == "pemasukan" && t.jenis != JenisTransaksi::Pemasukan {
                return false;
            }
            if j_lower == "pengeluaran" && t.jenis != JenisTransaksi::Pengeluaran {
                return false;
            }
            true
        });
    }

    let offset = query.offset.unwrap_or(0).max(0) as usize;
    let limit = query.limit.unwrap_or(0);
    if offset > 0 || limit > 0 {
        let limit = if limit > 0 {
            limit.min(500) as usize
        } else {
            hasil.len()
        };
        hasil = hasil.into_iter().skip(offset).take(limit).collect();
    }

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<TransaksiModel>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} transaksi.", hasil.len()),
            data: Some(hasil),
        }),
    )
        .into_response()
}

// 5b. DETAIL TRANSAKSI (item, refund, dan sisa yang dapat direfund)
pub async fn get_transaksi_detail(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    use rust_decimal::prelude::ToPrimitive;

    let header = sqlx::query_as::<
        _,
        (
            i32,
            i32,
            String,
            chrono::NaiveDateTime,
            rust_decimal::Decimal,
            String,
            String,
            Option<String>,
            Option<String>,
        ),
    >(
        "SELECT t.id, t.unit_id, u.nama, t.tanggal, t.total, t.metode_bayar, t.status,
                t.customer_name, t.notes
         FROM transactions t
         JOIN business_units u ON u.id = t.unit_id
         WHERE t.id = $1 AND u.owner_id = $2",
    )
    .bind(id as i32)
    .bind(claims.owner_id as i32)
    .fetch_optional(&state.db)
    .await
    .unwrap_or(None);

    let Some(header) = header else {
        return (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<TransaksiDetailModel> {
                status: "error".to_string(),
                message: "Transaksi tidak ditemukan.".to_string(),
                data: None,
            }),
        )
            .into_response();
    };
    if let Err(err) = ensure_unit_access(&state, &claims, header.1 as i64).await {
        return err;
    }

    let item_rows = sqlx::query_as::<
        _,
        (
            i32,
            Option<i32>,
            String,
            String,
            i32,
            rust_decimal::Decimal,
            rust_decimal::Decimal,
            i64,
        ),
    >(
        "SELECT ti.id, ti.product_id, COALESCE(ti.item_name, '-'),
                COALESCE(ti.item_type, 'barang'), ti.qty, ti.harga_satuan, ti.subtotal,
                COALESCE((SELECT SUM(ri.qty) FROM transaction_refund_items ri
                          WHERE ri.transaction_item_id = ti.id), 0)::bigint
         FROM transaction_items ti
         WHERE ti.trx_id = $1
         ORDER BY ti.id ASC",
    )
    .bind(id as i32)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let items: Vec<TransaksiItemDetailModel> = item_rows
        .into_iter()
        .map(|r| {
            let refunded = r.7.max(0) as i32;
            TransaksiItemDetailModel {
                id: r.0 as i64,
                product_id: r.1.map(|v| v as i64),
                item_name: r.2,
                item_type: r.3,
                qty: r.4,
                harga_satuan: r.5.to_f64().unwrap_or_default(),
                subtotal: r.6.to_f64().unwrap_or_default(),
                refunded_qty: refunded,
                refundable_qty: (r.4 - refunded).max(0),
            }
        })
        .collect();

    let refund_rows = sqlx::query_as::<
        _,
        (
            i32,
            i32,
            String,
            String,
            rust_decimal::Decimal,
            String,
            chrono::NaiveDateTime,
        ),
    >(
        "SELECT id, transaction_id, jenis, alasan, jumlah, aktor, created_at
         FROM transaction_refunds WHERE transaction_id = $1 ORDER BY id ASC",
    )
    .bind(id as i32)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let refund_item_rows = sqlx::query_as::<
        _,
        (
            i32,
            i32,
            Option<i32>,
            String,
            String,
            i32,
            rust_decimal::Decimal,
        ),
    >(
        "SELECT ri.refund_id, ri.transaction_item_id, ri.product_id, ri.item_name,
                ri.item_type, ri.qty, ri.jumlah
         FROM transaction_refund_items ri
         JOIN transaction_refunds r ON r.id = ri.refund_id
         WHERE r.transaction_id = $1 ORDER BY ri.id ASC",
    )
    .bind(id as i32)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let mut items_by_refund: std::collections::HashMap<i32, Vec<RefundItemModel>> =
        std::collections::HashMap::new();
    for row in refund_item_rows {
        items_by_refund
            .entry(row.0)
            .or_default()
            .push(RefundItemModel {
                transaction_item_id: row.1 as i64,
                product_id: row.2.map(|v| v as i64),
                item_name: row.3,
                item_type: row.4,
                qty: row.5,
                jumlah: row.6.to_f64().unwrap_or_default(),
            });
    }

    let refunded_total: f64 = refund_rows
        .iter()
        .map(|r| r.4.to_f64().unwrap_or_default())
        .sum();
    let refunds: Vec<RefundModel> = refund_rows
        .into_iter()
        .map(|r| RefundModel {
            id: r.0 as i64,
            transaction_id: r.1 as i64,
            unit_id: header.1 as i64,
            jenis: r.2,
            alasan: r.3,
            jumlah: r.4.to_f64().unwrap_or_default(),
            aktor: r.5,
            created_at: r.6.format("%Y-%m-%d %H:%M").to_string(),
            items: items_by_refund.remove(&r.0).unwrap_or_default(),
        })
        .collect();

    let total = header.4.to_f64().unwrap_or_default();
    let detail = TransaksiDetailModel {
        id: header.0 as i64,
        owner_id: claims.owner_id,
        unit_id: header.1 as i64,
        nama_unit: header.2,
        tanggal: header.3.format("%Y-%m-%d %H:%M").to_string(),
        total,
        metode_bayar: header.5,
        status: header.6,
        customer_name: header.7,
        notes: header.8,
        items,
        refunds,
        refunded_total: bulatkan_dua(refunded_total),
        refundable_total: bulatkan_dua((total - refunded_total).max(0.0)),
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<TransaksiDetailModel> {
            status: "success".to_string(),
            message: "Detail transaksi berhasil dimuat.".to_string(),
            data: Some(detail),
        }),
    )
        .into_response()
}

// 5c. REFUND / VOID TRANSAKSI (atomic, idempoten per transaksi, tanpa menghapus transaksi asli)
pub async fn refund_transaksi(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Path(id): Path<i64>,
    Json(payload): Json<RefundTransaksiRequest>,
) -> impl IntoResponse {
    use rust_decimal::prelude::ToPrimitive;
    use std::collections::{HashMap, HashSet};

    if !["owner", "manager"].contains(&claims.role.as_str()) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<RefundModel> {
                status: "error".to_string(),
                message: "Hanya Owner atau Manager yang berwenang melakukan refund.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    let alasan = payload.alasan.trim().to_string();
    if alasan.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<RefundModel> {
                status: "error".to_string(),
                message: "Alasan refund wajib diisi.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    let header = sqlx::query_as::<_, (i32, rust_decimal::Decimal, String)>(
        "SELECT t.unit_id, t.total, t.status
         FROM transactions t JOIN business_units u ON u.id = t.unit_id
         WHERE t.id = $1 AND u.owner_id = $2",
    )
    .bind(id as i32)
    .bind(claims.owner_id as i32)
    .fetch_optional(&state.db)
    .await
    .unwrap_or(None);
    let Some((unit_id, _, _)) = header else {
        return (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<RefundModel> {
                status: "error".to_string(),
                message: "Transaksi tidak ditemukan.".to_string(),
                data: None,
            }),
        )
            .into_response();
    };
    if let Err(err) = ensure_unit_access(&state, &claims, unit_id as i64).await {
        return err;
    }

    let result: Result<RefundModel, (StatusCode, String)> = async {
        let mut tx = state
            .db
            .begin()
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

        let (unit_id, total_dec, status): (i32, rust_decimal::Decimal, String) =
            sqlx::query_as(
                "SELECT t.unit_id, t.total, t.status FROM transactions t
                 WHERE t.id = $1 FOR UPDATE",
            )
            .bind(id as i32)
            .fetch_one(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
        if status != "selesai" {
            return Err((
                StatusCode::CONFLICT,
                "Hanya transaksi berstatus selesai yang dapat direfund.".to_string(),
            ));
        }
        let total = total_dec.to_f64().unwrap_or_default();

        let already_refunded: rust_decimal::Decimal = sqlx::query_scalar(
            "SELECT COALESCE(SUM(jumlah), 0) FROM transaction_refunds WHERE transaction_id = $1",
        )
        .bind(id as i32)
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
        let already = already_refunded.to_f64().unwrap_or_default();
        if already >= total - 0.005 {
            return Err((
                StatusCode::CONFLICT,
                "Transaksi sudah direfund penuh.".to_string(),
            ));
        }

        let item_rows = sqlx::query_as::<
            _,
            (
                i32,
                Option<i32>,
                String,
                String,
                i32,
                rust_decimal::Decimal,
                rust_decimal::Decimal,
                i64,
            ),
        >(
            "SELECT ti.id, ti.product_id, COALESCE(ti.item_name, '-'),
                    COALESCE(ti.item_type, 'barang'), ti.qty, ti.harga_satuan, ti.subtotal,
                    COALESCE((SELECT SUM(ri.qty) FROM transaction_refund_items ri
                              WHERE ri.transaction_item_id = ti.id), 0)::bigint
             FROM transaction_items ti
             WHERE ti.trx_id = $1
             ORDER BY ti.id ASC
             FOR UPDATE OF ti",
        )
        .bind(id as i32)
        .fetch_all(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
        if item_rows.is_empty() {
            return Err((
                StatusCode::CONFLICT,
                "Transaksi tidak memiliki item untuk direfund.".to_string(),
            ));
        }

        let mut request_qty: HashMap<i32, i32> = HashMap::new();
        if payload.void {
            for row in &item_rows {
                let sisa = row.4 - row.7.max(0) as i32;
                if sisa > 0 {
                    request_qty.insert(row.0, sisa);
                }
            }
        } else {
            if payload.items.is_empty() {
                return Err((
                    StatusCode::BAD_REQUEST,
                    "Pilih minimal satu item untuk direfund.".to_string(),
                ));
            }
            let mut seen = HashSet::new();
            for item in &payload.items {
                if !seen.insert(item.transaction_item_id) {
                    return Err((
                        StatusCode::BAD_REQUEST,
                        "Item refund duplikat dalam satu permintaan.".to_string(),
                    ));
                }
                if item.qty <= 0 {
                    return Err((
                        StatusCode::BAD_REQUEST,
                        "Jumlah refund per item harus lebih besar dari nol.".to_string(),
                    ));
                }
                request_qty.insert(item.transaction_item_id as i32, item.qty);
            }
        }
        if request_qty.is_empty() {
            return Err((
                StatusCode::CONFLICT,
                "Tidak ada item yang masih dapat direfund.".to_string(),
            ));
        }

        let sum_subtotal: f64 = item_rows
            .iter()
            .map(|r| r.6.to_f64().unwrap_or_default())
            .sum();
        let faktor = if sum_subtotal > 0.0 {
            (total / sum_subtotal).clamp(0.0, 1.0)
        } else {
            1.0
        };

        let mut total_refund = 0.0;
        let mut rencana: Vec<(i32, Option<i32>, String, String, i32, f64)> = Vec::new();
        for row in &item_rows {
            let Some(qty) = request_qty.get(&row.0).copied() else {
                continue;
            };
            let refunded = row.7.max(0) as i32;
            let sisa = row.4 - refunded;
            if qty > sisa {
                return Err((
                    StatusCode::BAD_REQUEST,
                    format!(
                        "Jumlah refund item '{}' melebihi sisa yang dapat direfund ({}).",
                        row.2, sisa
                    ),
                ));
            }
            let subtotal = row.6.to_f64().unwrap_or_default();
            let nilai = hitung_nilai_refund(subtotal, row.4, qty, faktor);
            if nilai <= 0.0 {
                continue;
            }
            total_refund += nilai;
            rencana.push((row.0, row.1, row.2.clone(), row.3.clone(), qty, nilai));
        }

        if payload.void {
            let seluruh_sisa_terpilih = item_rows.iter().all(|row| {
                let sisa = row.4 - row.7.max(0) as i32;
                sisa <= 0 || request_qty.get(&row.0).copied().unwrap_or(0) == sisa
            });
            if seluruh_sisa_terpilih {
                total_refund = (total - already).max(0.0);
            }
        }
        total_refund = bulatkan_dua(total_refund);
        if !refund_masih_boleh(total, already, total_refund) {
            return Err((
                StatusCode::BAD_REQUEST,
                "Total refund melebihi nilai transaksi yang belum direfund.".to_string(),
            ));
        }

        let jumlah_dec =
            rust_decimal::Decimal::from_f64_retain(total_refund).unwrap_or_default();
        let (refund_id, created_at): (i32, chrono::NaiveDateTime) = sqlx::query_as(
            "INSERT INTO transaction_refunds
             (transaction_id, owner_id, unit_id, jenis, status, alasan, jumlah, aktor_id, aktor)
             VALUES ($1, $2, $3, $4, 'selesai', $5, $6, $7, $8)
             RETURNING id, created_at",
        )
        .bind(id as i32)
        .bind(claims.owner_id as i32)
        .bind(unit_id)
        .bind(if payload.void { "void" } else { "refund" })
        .bind(&alasan)
        .bind(jumlah_dec)
        .bind(claims.user_id as i32)
        .bind(&claims.sub)
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

        let mut refund_items = Vec::new();
        for (item_id, product_id, item_name, item_type, qty, nilai) in rencana {
            let nilai_dec = rust_decimal::Decimal::from_f64_retain(nilai).unwrap_or_default();
            sqlx::query(
                "INSERT INTO transaction_refund_items
                 (refund_id, transaction_item_id, product_id, item_name, item_type, qty, jumlah)
                 VALUES ($1, $2, $3, $4, $5, $6, $7)",
            )
            .bind(refund_id)
            .bind(item_id)
            .bind(product_id)
            .bind(&item_name)
            .bind(&item_type)
            .bind(qty)
            .bind(nilai_dec)
            .execute(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

            if item_type.eq_ignore_ascii_case("barang") {
                if let Some(pid) = product_id.filter(|v| *v > 0) {
                    let inv_id: i32 = sqlx::query_scalar(
                        "INSERT INTO inventories (unit_id, product_id, qty, min_stock)
                         VALUES ($1, $2, $3, 5)
                         ON CONFLICT (unit_id, product_id)
                         DO UPDATE SET qty = inventories.qty + EXCLUDED.qty
                         RETURNING id",
                    )
                    .bind(unit_id)
                    .bind(pid)
                    .bind(qty)
                    .fetch_one(&mut *tx)
                    .await
                    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
                    sqlx::query(
                        "INSERT INTO stock_movements
                         (inventory_id, tipe, qty, tanggal, unit_tujuan_id, dicatat_oleh,
                          status, waktu_terima, created_at)
                         VALUES ($1, 'masuk', $2, now(), $3, $4, 'diterima', now(), now())",
                    )
                    .bind(inv_id)
                    .bind(qty)
                    .bind(unit_id)
                    .bind(claims.user_id as i32)
                    .execute(&mut *tx)
                    .await
                    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
                }
            }

            refund_items.push(RefundItemModel {
                transaction_item_id: item_id as i64,
                product_id: product_id.map(|v| v as i64),
                item_name,
                item_type,
                qty,
                jumlah: nilai,
            });
        }

        sqlx::query(
            "INSERT INTO audit_logs (owner_id, aktor, role, aksi, modul, target, detail)
             VALUES ($1, $2, $3, $4, 'POS', $5, $6)",
        )
        .bind(claims.owner_id as i32)
        .bind(&claims.sub)
        .bind(&claims.role)
        .bind(if payload.void {
            "Void transaksi"
        } else {
            "Refund transaksi"
        })
        .bind(format!("Transaksi #{}", id))
        .bind(format!(
            "{} senilai {} dengan alasan: {}",
            if payload.void { "Void" } else { "Refund" },
            total_refund,
            alasan
        ))
        .execute(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

        tx.commit()
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

        Ok(RefundModel {
            id: refund_id as i64,
            transaction_id: id,
            unit_id: unit_id as i64,
            jenis: if payload.void { "void" } else { "refund" }.to_string(),
            alasan,
            jumlah: total_refund,
            aktor: claims.sub.clone(),
            created_at: created_at.format("%Y-%m-%d %H:%M").to_string(),
            items: refund_items,
        })
    }
    .await;

    match result {
        Ok(refund) => (
            StatusCode::CREATED,
            Json(ApiResponse::<RefundModel> {
                status: "success".to_string(),
                message: "Refund berhasil diproses dan transaksi asli tetap tersimpan.".to_string(),
                data: Some(refund),
            }),
        )
            .into_response(),
        Err((status, message)) => (
            status,
            Json(ApiResponse::<RefundModel> {
                status: "error".to_string(),
                message,
                data: None,
            }),
        )
            .into_response(),
    }
}

// 6. CATAT TRANSAKSI MANUAL (Pemasukan / Pengeluaran Umum)
pub async fn create_transaksi_manual(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Json(payload): Json<CreateTransaksiManualRequest>,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;
    let aktor_nama = claims.sub.clone();
    let aktor_role = claims.role.clone();

    // Hanya pemilik/manajer yang boleh mencatat mutasi keuangan manual.
    if !["owner", "manager"].contains(&aktor_role.as_str()) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<TransaksiModel> {
                status: "error".to_string(),
                message: "Role Anda tidak berwenang mencatat transaksi keuangan.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    if !(payload.jumlah.is_finite() && payload.jumlah > 0.0) {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<TransaksiModel> {
                status: "error".to_string(),
                message: "Jumlah transaksi harus lebih besar dari 0.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    if payload.kategori.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<TransaksiModel> {
                status: "error".to_string(),
                message: "Kategori transaksi wajib diisi.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    if let Err(err) = ensure_unit_access(&state, &claims, payload.unit_id).await {
        return err;
    }

    // Validasi kepemilikan unit & ambil namanya langsung dari database.
    let nama_unit: Option<String> =
        sqlx::query_scalar("SELECT nama FROM business_units WHERE id = $1 AND owner_id = $2")
            .bind(payload.unit_id as i32)
            .bind(owner_id as i32)
            .fetch_optional(&state.db)
            .await
            .unwrap_or(None);

    let Some(nama_unit) = nama_unit else {
        return (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<TransaksiModel> {
                status: "error".to_string(),
                message: "Unit usaha tidak ditemukan atau bukan milik bisnis Anda.".to_string(),
                data: None,
            }),
        )
            .into_response();
    };

    let jenis_str = match payload.jenis {
        JenisTransaksi::Pemasukan => "masuk",
        JenisTransaksi::Pengeluaran => "keluar",
    };
    let jumlah_dec = rust_decimal::Decimal::from_f64_retain(payload.jumlah).unwrap_or_default();

    let mut tx = match state.db.begin().await {
        Ok(t) => t,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<TransaksiModel> {
                    status: "error".to_string(),
                    message: format!("Gagal memulai transaksi database: {}", e),
                    data: None,
                }),
            )
                .into_response();
        }
    };

    // Simpan permanen ke cash_flows
    let inserted: Result<(i32, chrono::NaiveDateTime), sqlx::Error> = sqlx::query_as(
        "INSERT INTO cash_flows (unit_id, tanggal, jenis, kategori, jumlah)
         VALUES ($1, CURRENT_DATE, $2, $3, $4)
         RETURNING id, created_at",
    )
    .bind(payload.unit_id as i32)
    .bind(jenis_str)
    .bind(payload.kategori.trim())
    .bind(jumlah_dec)
    .fetch_one(&mut *tx)
    .await;

    let (new_id, created_at) = match inserted {
        Ok(r) => r,
        Err(e) => {
            let _ = tx.rollback().await;
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<TransaksiModel> {
                    status: "error".to_string(),
                    message: format!("Gagal menyimpan transaksi: {}", e),
                    data: None,
                }),
            )
                .into_response();
        }
    };

    // Sinkronkan agregat keuangan unit usaha dengan pengecekan periode bulan berjalan
    let is_masuk = jenis_str == "masuk";
    let _ = sqlx::query(
        "UPDATE business_units
         SET
             pendapatan_bulan_ini = CASE
                 WHEN COALESCE(periode_omzet, '') = to_char(CURRENT_DATE, 'YYYY-MM')
                     THEN COALESCE(pendapatan_bulan_ini, 0) + CASE WHEN $1 THEN $2 ELSE 0 END
                 ELSE CASE WHEN $1 THEN $2 ELSE 0 END
             END,
             pengeluaran_bulan_ini = CASE
                 WHEN COALESCE(periode_omzet, '') = to_char(CURRENT_DATE, 'YYYY-MM')
                     THEN COALESCE(pengeluaran_bulan_ini, 0) + CASE WHEN NOT $1 THEN $2 ELSE 0 END
                 ELSE CASE WHEN NOT $1 THEN $2 ELSE 0 END
             END,
             periode_omzet = to_char(CURRENT_DATE, 'YYYY-MM')
         WHERE id = $3",
    )
    .bind(is_masuk)
    .bind(jumlah_dec)
    .bind(payload.unit_id as i32)
    .execute(&mut *tx)
    .await;

    // Audit log permanen
    let _ = sqlx::query(
        "INSERT INTO audit_logs (owner_id, aktor, role, aksi, modul, target, detail, waktu)
         VALUES ($1, $2, $3, $4, 'Keuangan', $5, $6, now())",
    )
    .bind(owner_id as i32)
    .bind(&aktor_nama)
    .bind(&aktor_role)
    .bind(format!("Catat Transaksi {:?}", payload.jenis))
    .bind(&nama_unit)
    .bind(format!(
        "Transaksi #{} senilai Rp {:.0}",
        new_id, payload.jumlah
    ))
    .execute(&mut *tx)
    .await;

    if let Err(e) = tx.commit().await {
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<TransaksiModel> {
                status: "error".to_string(),
                message: format!("Gagal menyimpan transaksi: {}", e),
                data: None,
            }),
        )
            .into_response();
    }

    let new_trx = TransaksiModel {
        id: new_id as i64,
        owner_id,
        unit_id: payload.unit_id,
        nama_unit,
        tanggal: created_at.format("%Y-%m-%d %H:%M").to_string(),
        jenis: payload.jenis,
        kategori: payload.kategori,
        jumlah: payload.jumlah,
        keterangan: if payload.keterangan.trim().is_empty() {
            "Transaksi Manual".to_string()
        } else {
            payload.keterangan
        },
        metode_pembayaran: Some("Manual".to_string()),
        items: None,
    };

    (
        StatusCode::CREATED,
        Json(ApiResponse::<TransaksiModel> {
            status: "success".to_string(),
            message: "Transaksi berhasil dicatat dan keuangan unit usaha telah disinkronkan."
                .to_string(),
            data: Some(new_trx),
        }),
    )
        .into_response()
}

// ==================== LIFECYCLE RENTAL & JASA HANDLERS ====================

// 7. DAFTAR PESANAN RENTAL & JASA AKTIF / BERJALAN
pub async fn list_active_orders(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Query(query): Query<TransaksiQuery>,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;

    #[derive(sqlx::FromRow)]
    struct OrderDbRow {
        id: i32,
        trx_id: i32,
        unit_id: i32,
        product_id: Option<i32>,
        item_name: String,
        order_type: String,
        customer_name: Option<String>,
        start_time: chrono::NaiveDateTime,
        expected_end_time: chrono::NaiveDateTime,
        actual_end_time: Option<chrono::NaiveDateTime>,
        duration: i32,
        duration_unit: String,
        qty: i32,
        status: String,
        assigned_staff: Option<String>,
        deposit_amount: Option<rust_decimal::Decimal>,
        penalty_fee: Option<rust_decimal::Decimal>,
        notes: Option<String>,
    }

    if let Some(uid) = query.unit_id {
        if let Err(err) = ensure_unit_access(&state, &claims, uid).await {
            return err;
        }
    }
    let scoped_ids =
        if query.unit_id.is_none() && !["owner", "auditor"].contains(&claims.role.as_str()) {
            match accessible_unit_ids(&state, &claims).await {
                Ok(ids) => Some(ids),
                Err(err) => return err,
            }
        } else {
            None
        };

    // Ambil order rental & jasa yang belum selesai dari PostgreSQL
    let rows = if let Some(uid) = query.unit_id {
        sqlx::query_as::<_, OrderDbRow>(
            "SELECT o.id, o.trx_id, o.unit_id, o.product_id, o.item_name, o.order_type,
                    o.customer_name, o.start_time, o.expected_end_time, o.actual_end_time,
                    o.duration, o.duration_unit, o.qty, o.status, o.assigned_staff,
                    o.deposit_amount, o.penalty_fee, o.notes
             FROM rental_service_orders o
             JOIN business_units u ON u.id = o.unit_id
             WHERE u.owner_id = $1 AND o.unit_id = $2
               AND o.status NOT IN ('returned', 'completed', 'cancelled')
             ORDER BY o.expected_end_time ASC",
        )
        .bind(owner_id as i32)
        .bind(uid as i32)
        .fetch_all(&state.db)
        .await
    } else if let Some(ids) = &scoped_ids {
        sqlx::query_as::<_, OrderDbRow>(
            "SELECT o.id, o.trx_id, o.unit_id, o.product_id, o.item_name, o.order_type,
                    o.customer_name, o.start_time, o.expected_end_time, o.actual_end_time,
                    o.duration, o.duration_unit, o.qty, o.status, o.assigned_staff,
                    o.deposit_amount, o.penalty_fee, o.notes
             FROM rental_service_orders o
             JOIN business_units u ON u.id = o.unit_id
             WHERE u.owner_id = $1 AND o.unit_id = ANY($2)
               AND o.status NOT IN ('returned', 'completed', 'cancelled')
             ORDER BY o.expected_end_time ASC",
        )
        .bind(owner_id as i32)
        .bind(ids)
        .fetch_all(&state.db)
        .await
    } else {
        sqlx::query_as::<_, OrderDbRow>(
            "SELECT o.id, o.trx_id, o.unit_id, o.product_id, o.item_name, o.order_type,
                    o.customer_name, o.start_time, o.expected_end_time, o.actual_end_time,
                    o.duration, o.duration_unit, o.qty, o.status, o.assigned_staff,
                    o.deposit_amount, o.penalty_fee, o.notes
             FROM rental_service_orders o
             JOIN business_units u ON u.id = o.unit_id
             WHERE u.owner_id = $1
               AND o.status NOT IN ('returned', 'completed', 'cancelled')
             ORDER BY o.expected_end_time ASC",
        )
        .bind(owner_id as i32)
        .fetch_all(&state.db)
        .await
    };

    use rust_decimal::prelude::ToPrimitive;
    let hasil: Vec<RentalServiceOrderModel> = match rows {
        Ok(list) => {
            let now = chrono::Local::now().naive_local();
            list.into_iter()
                .map(|r| {
                    let mut st = r.status;
                    // Auto-flag jika sewa aktif telah melewati expected_end_time
                    if r.order_type == "rental" && st == "active" && r.expected_end_time < now {
                        st = "overdue".to_string();
                    }

                    RentalServiceOrderModel {
                        id: r.id as i64,
                        trx_id: r.trx_id as i64,
                        unit_id: r.unit_id as i64,
                        product_id: r.product_id.map(|p| p as i64),
                        item_name: r.item_name,
                        order_type: r.order_type,
                        customer_name: r.customer_name,
                        start_time: r.start_time.format("%Y-%m-%d %H:%M").to_string(),
                        expected_end_time: r.expected_end_time.format("%Y-%m-%d %H:%M").to_string(),
                        actual_end_time: r
                            .actual_end_time
                            .map(|t| t.format("%Y-%m-%d %H:%M").to_string()),
                        duration: r.duration,
                        duration_unit: r.duration_unit,
                        qty: r.qty,
                        status: st,
                        assigned_staff: r.assigned_staff,
                        deposit_amount: r.deposit_amount.and_then(|d| d.to_f64()).unwrap_or(0.0),
                        penalty_fee: r.penalty_fee.and_then(|d| d.to_f64()).unwrap_or(0.0),
                        notes: r.notes,
                    }
                })
                .collect()
        }
        Err(e) => {
            tracing::error!("Gagal mengambil active rental/service orders: {}", e);
            Vec::new()
        }
    };

    Json(ApiResponse::<Vec<RentalServiceOrderModel>> {
        status: "success".to_string(),
        message: "Daftar pesanan sewa dan jasa berhasil diambil.".to_string(),
        data: Some(hasil),
    })
    .into_response()
}

// 8. PENGEMBALIAN BARANG SEWA (RETURN RENTAL)
pub async fn return_rental(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Json(payload): Json<ReturnRentalRequest>,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;

    // Ambil order beserta status, unit, produk, dan qty untuk restore stok
    let order_info: Option<(i32, Option<i32>, String, String, Option<String>, i32)> =
        sqlx::query_as(
            "SELECT o.unit_id, o.product_id, o.item_name, o.status, o.customer_name, o.qty
         FROM rental_service_orders o
         JOIN business_units u ON u.id = o.unit_id
         WHERE o.id = $1 AND u.owner_id = $2 AND o.order_type = 'rental'",
        )
        .bind(payload.order_id as i32)
        .bind(owner_id as i32)
        .fetch_optional(&state.db)
        .await
        .unwrap_or(None);

    let Some((unit_id, product_id, item_name, status, cust, qty)) = order_info else {
        return (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Pesanan sewa tidak ditemukan atau bukan milik bisnis Anda.".to_string(),
                data: None,
            }),
        )
            .into_response();
    };

    if let Err(err) = ensure_unit_access(&state, &claims, unit_id as i64).await {
        return err;
    }

    // Cegah pengembalian ganda / manipulasi status order yang sudah selesai
    if !["active", "overdue"].contains(&status.as_str()) {
        return (
            StatusCode::CONFLICT,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: format!(
                    "Pesanan sewa #{} sudah berstatus '{}' dan tidak dapat dikembalikan lagi.",
                    payload.order_id, status
                ),
                data: None,
            }),
        )
            .into_response();
    }

    let penalty = payload.penalty_fee.unwrap_or(0.0);
    if penalty < 0.0 {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Denda tidak boleh negatif.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    let penalty_dec = rust_decimal::Decimal::from_f64_retain(penalty).unwrap_or_default();
    let qty_restore = qty.max(1);

    // Proses atomik: ubah status, pulihkan stok inventori, dan catat mutasi masuk.
    let mut tx = match state.db.begin().await {
        Ok(t) => t,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<()> {
                    status: "error".to_string(),
                    message: format!("Gagal memulai transaksi database: {}", e),
                    data: None,
                }),
            )
                .into_response();
        }
    };

    let updated = sqlx::query(
        "UPDATE rental_service_orders
         SET status = 'returned', actual_end_time = now(), penalty_fee = $1,
             notes = COALESCE(notes, '') || ' [Dikembalikan: ' || COALESCE($2, 'Sesuai kondisi') || ']'
         WHERE id = $3 AND status IN ('active', 'overdue')",
    )
    .bind(penalty_dec)
    .bind(payload.notes.clone())
    .bind(payload.order_id as i32)
    .execute(&mut *tx)
    .await;

    match updated {
        Ok(r) if r.rows_affected() > 0 => {}
        Ok(_) => {
            let _ = tx.rollback().await;
            return (
                StatusCode::CONFLICT,
                Json(ApiResponse::<()> {
                    status: "error".to_string(),
                    message: "Pesanan sewa sudah diproses oleh transaksi lain.".to_string(),
                    data: None,
                }),
            )
                .into_response();
        }
        Err(e) => {
            let _ = tx.rollback().await;
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<()> {
                    status: "error".to_string(),
                    message: format!("Gagal memperbarui status sewa: {}", e),
                    data: None,
                }),
            )
                .into_response();
        }
    }

    // Pulihkan stok hanya untuk aset rental yang terhubung ke produk inventori.
    if let Some(pid) = product_id {
        let inv_row: Result<Option<(i32,)>, sqlx::Error> = sqlx::query_as(
            "UPDATE inventories SET qty = qty + $1
             WHERE unit_id = $2 AND product_id = $3
             RETURNING id",
        )
        .bind(qty_restore)
        .bind(unit_id)
        .bind(pid)
        .fetch_optional(&mut *tx)
        .await;

        match inv_row {
            Ok(Some((inv_id,))) => {
                let _ = sqlx::query(
                    "INSERT INTO stock_movements (inventory_id, tipe, qty, tanggal, unit_tujuan_id, created_at)
                     VALUES ($1, 'masuk', $2, now(), $3, now())",
                )
                .bind(inv_id)
                .bind(qty_restore)
                .bind(unit_id)
                .execute(&mut *tx)
                .await;
            }
            Ok(None) => {
                tracing::warn!(
                    "Inventori untuk produk #{} di unit #{} tidak ditemukan saat restore stok rental.",
                    pid,
                    unit_id
                );
            }
            Err(e) => {
                let _ = tx.rollback().await;
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiResponse::<()> {
                        status: "error".to_string(),
                        message: format!("Gagal memulihkan stok inventori: {}", e),
                        data: None,
                    }),
                )
                    .into_response();
            }
        }
    }

    // Catat ke audit trail (dalam transaksi yang sama)
    let _ = sqlx::query(
        "INSERT INTO audit_logs (owner_id, aktor, role, aksi, modul, target, detail, waktu)
         VALUES ($1, $2, 'kasir', 'Pengembalian Sewa', 'Kasir', $3, $4, now())",
    )
    .bind(owner_id as i32)
    .bind(&claims.sub)
    .bind(format!("Order Sewa #{}", payload.order_id))
    .bind(format!(
        "Barang \"{}\" telah dikembalikan oleh {}. Qty: {}. Denda keterlambatan/kerusakan: Rp {:.0}",
        item_name,
        cust.unwrap_or_else(|| "Pelanggan".to_string()),
        qty_restore,
        penalty
    ))
    .execute(&mut *tx)
    .await;

    if let Err(e) = tx.commit().await {
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: format!("Gagal menyimpan pengembalian sewa: {}", e),
                data: None,
            }),
        )
            .into_response();
    }

    (
        StatusCode::OK,
        Json(ApiResponse::<()> {
            status: "success".to_string(),
            message: format!(
                "Barang sewa \"{}\" berhasil dikembalikan ke inventori! (Denda: Rp {:.0})",
                item_name, penalty
            ),
            data: None,
        }),
    )
        .into_response()
}

// 9. UPDATE STATUS JASA / LAYANAN / SERVIS (BERIKUT PENUGASAN PETUGAS/TEKNISI)
pub async fn update_service_status(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Json(payload): Json<UpdateServiceStatusRequest>,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;

    let order_unit: Option<i64> = sqlx::query_scalar(
        "SELECT o.unit_id::bigint FROM rental_service_orders o JOIN business_units u ON u.id = o.unit_id
         WHERE o.id = $1 AND u.owner_id = $2 AND o.order_type = 'service'"
    ).bind(payload.order_id).bind(owner_id).fetch_optional(&state.db).await.unwrap_or(None);
    let Some(order_unit) = order_unit else {
        return (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Order layanan jasa tidak ditemukan.".to_string(),
                data: None,
            }),
        )
            .into_response();
    };
    if let Err(err) = ensure_unit_access(&state, &claims, order_unit).await {
        return err;
    }

    let valid_status = ["queued", "in_progress", "ready", "completed", "cancelled"];
    if !valid_status.contains(&payload.status.as_str()) {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message:
                    "Status layanan tidak valid. Pilihan: queued, in_progress, ready, completed"
                        .to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    let is_done = payload.status == "completed" || payload.status == "cancelled";

    let res = sqlx::query(
        "UPDATE rental_service_orders
         SET status = $1,
             assigned_staff = COALESCE($2, assigned_staff),
             actual_end_time = CASE WHEN $3 THEN now() ELSE actual_end_time END,
             notes = CASE WHEN $4 IS NOT NULL THEN COALESCE(notes, '') || ' [' || $4 || ']' ELSE notes END
         WHERE id = $5 AND unit_id IN (SELECT id FROM business_units WHERE owner_id = $6)
           AND order_type = 'service'",
    )
    .bind(&payload.status)
    .bind(payload.assigned_staff)
    .bind(is_done)
    .bind(payload.notes)
    .bind(payload.order_id as i32)
    .bind(owner_id as i32)
    .execute(&state.db)
    .await;

    match res {
        Ok(r) if r.rows_affected() > 0 => (
            StatusCode::OK,
            Json(ApiResponse::<()> {
                status: "success".to_string(),
                message: format!(
                    "Status tugas layanan jasa berhasil diubah menjadi: {}",
                    payload.status.to_uppercase()
                ),
                data: None,
            }),
        )
            .into_response(),
        Ok(_) => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Order layanan jasa tidak ditemukan.".to_string(),
                data: None,
            }),
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: format!("Gagal update status layanan: {}", e),
                data: None,
            }),
        )
            .into_response(),
    }
}
