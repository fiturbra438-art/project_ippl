use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use chrono::Local;
use serde::Deserialize;
use std::sync::Arc;

use crate::auth::require_claims;
use crate::models::{
    JenisTransaksi, RentalServiceOrderModel, ShiftKasirModel, StatusShift, TransaksiModel,
};
use crate::schemas::{
    ApiResponse, BukaShiftRequest, CheckoutRequest, CreateTransaksiManualRequest,
    ReturnRentalRequest, TutupShiftRequest, UpdateServiceStatusRequest,
};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct TransaksiQuery {
    pub unit_id: Option<i64>,
    pub jenis: Option<String>,
}

// 1. STATUS SHIFT KASIR AKTIF (Membaca langsung dari tabel PostgreSQL cashier_shifts)
pub async fn get_shift_status(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(unit_id): Path<i64>,
) -> impl IntoResponse {
    use rust_decimal::prelude::ToPrimitive;

    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };

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
    headers: HeaderMap,
    Json(payload): Json<BukaShiftRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
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
    headers: HeaderMap,
    Json(payload): Json<TutupShiftRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let shift_valid: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM cashier_shifts s JOIN business_units u ON u.id = s.unit_id WHERE s.id = $1 AND u.owner_id = $2)"
    )
    .bind(payload.shift_id as i32)
    .bind(claims.owner_id as i32)
    .fetch_one(&state.db)
    .await
    .unwrap_or(false);
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
    headers: HeaderMap,
    Json(payload): Json<CheckoutRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;
    let user_id = claims.user_id;
    let _kasir_nama = claims.sub.clone();

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
    let catatan_transaksi = payload
        .notes
        .clone()
        .or_else(|| payload.keterangan.clone());
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

            // Ambil nama unit usaha
            let usahas = state.usahas.read().await;
            let nama_unit = usahas
                .iter()
                .find(|u| u.id == payload.unit_id)
                .map(|u| u.nama.clone())
                .unwrap_or_else(|| "Unit Usaha".to_string());
            drop(usahas);

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
    headers: HeaderMap,
    Query(query): Query<TransaksiQuery>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;

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
        sqlx::query_as::<_, (i32, i32, String, chrono::NaiveDateTime, String, String, rust_decimal::Decimal)>(
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
    } else {
        sqlx::query_as::<_, (i32, i32, String, chrono::NaiveDateTime, String, String, rust_decimal::Decimal)>(
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

// 6. CATAT TRANSAKSI MANUAL (Pemasukan / Pengeluaran Umum)
pub async fn create_transaksi_manual(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateTransaksiManualRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
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

    // Validasi kepemilikan unit & ambil namanya langsung dari database.
    let nama_unit: Option<String> = sqlx::query_scalar(
        "SELECT nama FROM business_units WHERE id = $1 AND owner_id = $2",
    )
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

    // Sinkronkan agregat keuangan unit usaha
    let kolom = if jenis_str == "masuk" {
        "pendapatan_bulan_ini"
    } else {
        "pengeluaran_bulan_ini"
    };
    let sync_sql = format!(
        "UPDATE business_units SET {} = COALESCE({}, 0) + $1 WHERE id = $2",
        kolom, kolom
    );
    let _ = sqlx::query(&sync_sql)
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
    headers: HeaderMap,
    Query(query): Query<TransaksiQuery>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
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
                        actual_end_time: r.actual_end_time.map(|t| t.format("%Y-%m-%d %H:%M").to_string()),
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
    headers: HeaderMap,
    Json(payload): Json<ReturnRentalRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;

    // Ambil order beserta status, unit, produk, dan qty untuk restore stok
    let order_info: Option<(i32, Option<i32>, String, String, Option<String>, i32)> = sqlx::query_as(
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
    headers: HeaderMap,
    Json(payload): Json<UpdateServiceStatusRequest>,
) -> impl IntoResponse {
    let claims = match require_claims(&headers, &state.jwt_secret) {
        Ok(c) => c,
        Err(err) => return err.into_response(),
    };
    let owner_id = claims.owner_id;

    let valid_status = ["queued", "in_progress", "ready", "completed", "cancelled"];
    if !valid_status.contains(&payload.status.as_str()) {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Status layanan tidak valid. Pilihan: queued, in_progress, ready, completed"
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
