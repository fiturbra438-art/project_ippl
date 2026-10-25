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
use crate::models::{AuditLogModel, JenisTransaksi, ShiftKasirModel, StatusShift, TransaksiModel};
use crate::schemas::{
    ApiResponse, BukaShiftRequest, CheckoutRequest, CreateTransaksiManualRequest, TutupShiftRequest,
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
    Path(unit_id): Path<i64>,
) -> impl IntoResponse {
    use rust_decimal::prelude::ToPrimitive;

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
        .bind(rust_decimal::Decimal::ZERO)
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
        let harga_server: Option<rust_decimal::Decimal> = sqlx::query_scalar(
            "SELECT p.harga_jual
             FROM products p
             JOIN inventories i ON i.product_id = p.id
             WHERE p.id = $1 AND p.owner_id = $2 AND i.unit_id = $3",
        )
        .bind(it.produk_id as i32)
        .bind(owner_id as i32)
        .bind(payload.unit_id as i32)
        .fetch_optional(&state.db)
        .await
        .unwrap_or(None);
        let Some(harga_server) = harga_server else {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<TransaksiModel> {
                    status: "error".to_string(),
                    message: "Produk tidak tersedia pada unit usaha yang dipilih.".to_string(),
                    data: None,
                }),
            )
                .into_response();
        };
        mapped_items.push(serde_json::json!({
            "product_id": it.produk_id,
            "qty": it.jumlah,
            "harga_satuan": harga_server
        }));
    }
    let items_json = serde_json::Value::Array(mapped_items);

    // Panggil Stored Procedure tunggal di PostgreSQL:
    // Stored Procedure di dalam database otomatis memanggil:
    // - Function fn_cek_ketersediaan_stok
    // - Function fn_hitung_total_belanja
    // - Trigger trg_kurangi_stok_inventaris
    // - Trigger trg_update_omzet_unit
    let result: Result<
        (
            Option<i32>,
            Option<rust_decimal::Decimal>,
            Option<String>,
            Option<String>,
        ),
        sqlx::Error,
    > = sqlx::query_as("CALL sp_proses_checkout_kasir($1, $2, $3, $4, NULL, NULL, NULL, NULL)")
        .bind(payload.unit_id as i32)
        .bind(user_id as i32)
        .bind(&payload.metode_pembayaran)
        .bind(items_json)
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

    // Gabungkan dengan transaksi manual di in-memory jika ada
    let transaksis = state.transaksis.read().await;
    for t in transaksis.iter() {
        if t.owner_id == owner_id {
            if let Some(uid) = query.unit_id {
                if uid > 0 && t.unit_id != uid {
                    continue;
                }
            }
            hasil.push(t.clone());
        }
    }
    drop(transaksis);

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

    let mut usahas = state.usahas.write().await;
    let nama_unit = match usahas.iter_mut().find(|u| u.id == payload.unit_id) {
        Some(u) => {
            if payload.jenis == JenisTransaksi::Pemasukan {
                u.pendapatan_bulan_ini += payload.jumlah;
            } else {
                u.pengeluaran_bulan_ini += payload.jumlah;
            }
            u.nama.clone()
        }
        None => {
            return (
                StatusCode::NOT_FOUND,
                Json(ApiResponse::<TransaksiModel> {
                    status: "error".to_string(),
                    message: "Unit usaha tidak ditemukan.".to_string(),
                    data: None,
                }),
            )
                .into_response();
        }
    };
    drop(usahas);

    let mut transaksis = state.transaksis.write().await;
    let new_id = (transaksis.len() as i64) + 1;
    let waktu_now = Local::now().format("%Y-%m-%d %H:%M").to_string();

    let new_trx = TransaksiModel {
        id: new_id,
        owner_id,
        unit_id: payload.unit_id,
        nama_unit: nama_unit.clone(),
        tanggal: waktu_now.clone(),
        jenis: payload.jenis.clone(),
        kategori: payload.kategori,
        jumlah: payload.jumlah,
        keterangan: payload.keterangan,
        metode_pembayaran: Some("Manual".to_string()),
        items: None,
    };

    transaksis.push(new_trx.clone());
    drop(transaksis);

    // Audit Log permanen ke PostgreSQL
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
        "Transaksi #{:?} senilai Rp {:.0}",
        new_id, payload.jumlah
    ))
    .execute(&state.db)
    .await;

    // Cache in-memory audit log
    let mut logs = state.audit_logs.write().await;
    let log_id = (logs.len() as i64) + 1;
    logs.push(AuditLogModel {
        id: log_id,
        owner_id,
        aktor: aktor_nama,
        role: aktor_role,
        aksi: format!("Catat Transaksi {:?}", payload.jenis),
        modul: "Keuangan".to_string(),
        target: nama_unit,
        detail: format!("Transaksi #{:?} senilai Rp {:.0}", new_id, payload.jumlah),
        waktu: waktu_now,
    });

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
