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
    AuditLogModel, JenisTransaksi, RentalServiceOrderModel, ShiftKasirModel, StatusShift,
    TransaksiModel,
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

        let tipe_item = it.tipe.clone().unwrap_or_else(|| "barang".to_string());
        let prod_id_opt = it.produk_id.filter(|&id| id > 0);

        // FITUR ANTI DOUBLE-BOOKING:
        // Jika item bertipe 'rental' dan memiliki ID produk fisik, cek apakah barang sedang dalam masa sewa aktif
        if tipe_item.to_lowercase() == "rental" {
            if let Some(pid) = prod_id_opt {
                let is_rented: Option<(i32, chrono::NaiveDateTime, Option<String>)> = sqlx::query_as(
                    "SELECT id, expected_end_time, customer_name
                     FROM rental_service_orders
                     WHERE product_id = $1 AND unit_id = $2 AND status = 'active'
                     LIMIT 1"
                )
                .bind(pid as i32)
                .bind(payload.unit_id as i32)
                .fetch_optional(&state.db)
                .await
                .unwrap_or(None);

                if let Some((_order_id, end_time, cust)) = is_rented {
                    let cust_name = cust.unwrap_or_else(|| "Pelanggan".to_string());
                    return (
                        StatusCode::CONFLICT,
                        Json(ApiResponse::<TransaksiModel> {
                            status: "error".to_string(),
                            message: format!(
                                "Barang ID #{} sedang dalam masa sewa aktif oleh {} sampai {}. Tidak dapat disewakan kembali sebelum dikembalikan!",
                                pid,
                                cust_name,
                                end_time.format("%Y-%m-%d %H:%M")
                            ),
                            data: None,
                        }),
                    )
                        .into_response();
                }
            }
        }

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

            if let Some((harga_db, nama_db)) = info_server {
                // Jika kasir memberikan harga satuan kustom (misal diskon atau nego), prioritaskan harga kasir
                let harga_satuan = if let Some(custom_h) = it.harga_satuan {
                    rust_decimal::Decimal::from_f64_retain(custom_h).unwrap_or(harga_db)
                } else {
                    harga_db
                };
                let nama_item = it.nama.clone().unwrap_or(nama_db);
                (harga_satuan, nama_item)
            } else {
                // Fallback jika id produk tidak ditemukan di tabel tertentu
                let fallback_h = it
                    .harga_satuan
                    .and_then(|h| rust_decimal::Decimal::from_f64_retain(h))
                    .unwrap_or_else(|| rust_decimal::Decimal::from(0));
                let fallback_n = it.nama.clone().unwrap_or_else(|| "Item Kustom".to_string());
                (fallback_h, fallback_n)
            }
        } else {
            // Item Ad-hoc / Jasa / Rental tanpa keterikatan produk inventori fisik
            let h = it
                .harga_satuan
                .and_then(|h| rust_decimal::Decimal::from_f64_retain(h))
                .unwrap_or_else(|| rust_decimal::Decimal::from(0));
            let n = it
                .nama
                .clone()
                .unwrap_or_else(|| format!("Layanan {}", tipe_item.to_uppercase()));
            (h, n)
        };

        mapped_items.push(serde_json::json!({
            "product_id": prod_id_opt.unwrap_or(0),
            "nama": nama_final,
            "tipe": tipe_item,
            "qty": it.jumlah,
            "harga_satuan": harga_final,
            "durasi": it.durasi.unwrap_or(1),
            "unit_durasi": it.unit_durasi.clone().unwrap_or_else(|| "jam".to_string()),
            "catatan": it.catatan.clone().unwrap_or_default()
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
                    o.duration, o.duration_unit, o.status, o.assigned_staff,
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
                    o.duration, o.duration_unit, o.status, o.assigned_staff,
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

    // Cek keberadaan order rental
    let order_info: Option<(i32, String, chrono::NaiveDateTime, Option<String>)> = sqlx::query_as(
        "SELECT o.id, o.item_name, o.expected_end_time, o.customer_name
         FROM rental_service_orders o
         JOIN business_units u ON u.id = o.unit_id
         WHERE o.id = $1 AND u.owner_id = $2 AND o.order_type = 'rental'",
    )
    .bind(payload.order_id as i32)
    .bind(owner_id as i32)
    .fetch_optional(&state.db)
    .await
    .unwrap_or(None);

    let Some((_id, item_name, _exp_time, cust)) = order_info else {
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

    let penalty = payload.penalty_fee.unwrap_or(0.0);
    let penalty_dec = rust_decimal::Decimal::from_f64_retain(penalty).unwrap_or_default();

    // Tandai status 'returned' dan simpan waktu aktual pengembalian
    let res = sqlx::query(
        "UPDATE rental_service_orders
         SET status = 'returned', actual_end_time = now(), penalty_fee = $1,
             notes = COALESCE(notes, '') || ' [Dikembalikan: ' || COALESCE($2, 'Sesuai kondisi') || ']'
         WHERE id = $3",
    )
    .bind(penalty_dec)
    .bind(payload.notes.clone())
    .bind(payload.order_id as i32)
    .execute(&state.db)
    .await;

    match res {
        Ok(_) => {
            // Catat ke audit trail
            let _ = sqlx::query(
                "INSERT INTO audit_logs (owner_id, aktor, role, aksi, modul, target, detail, waktu)
                 VALUES ($1, $2, 'kasir', 'Pengembalian Sewa', 'Kasir', $3, $4, now())"
            )
            .bind(owner_id as i32)
            .bind(&claims.sub)
            .bind(format!("Order Sewa #{}", payload.order_id))
            .bind(format!(
                "Barang \"{}\" telah dikembalikan oleh {}. Denda keterlambatan/kerusakan: Rp {:.0}",
                item_name,
                cust.unwrap_or_else(|| "Pelanggan".to_string()),
                penalty
            ))
            .execute(&state.db)
            .await;

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
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: format!("Gagal memproses pengembalian sewa: {}", e),
                data: None,
            }),
        )
            .into_response(),
    }
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

    let is_done = payload.status == "completed";

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
